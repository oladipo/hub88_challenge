defmodule Challenge.Worker do
  @moduledoc """
  challenge worker
  """
  use GenServer

  @type user :: %{
          amount: integer(),
          currency: integer(),
          ref: String.t()
        }

  def start_link(_) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init(_) do
    {:ok, %{users: [], bets: [], wins: []}}
  end

  @impl GenServer
  def handle_cast({:create_users, attrs}, %{users: users} = state) do
    new_users = create_users(attrs, users)

    {:noreply, %{state | users: new_users}}
  end

  def handle_cast(_message, state) do
    {:noreply, state}
  end

  @impl GenServer
  def handle_call({:bet, bet_params}, _from, %{bets: bets} = state) do
    with {:ok, resp, updated_users} <- place_bet(bet_params, state),
         updated_bets <- Map.update!(state, :bets, fn _ -> bets ++ [bet_params] end),
         updated_state <- Map.update!(updated_bets, :users, fn _ -> updated_users end) do
      {:reply, resp, updated_state}
    else
      {:error, resp} ->
        {:reply, resp, state}
    end
  end

  def handle_call({:win, win_params}, _from, %{wins: wins} = state) do
    with {:ok, resp, _updated_users} <- process_win(win_params, state),
         updated_state <- Map.update!(state, :wins, fn _ -> wins ++ [win_params] end) do
      {:reply, resp, updated_state}
    else
      {:error, resp} ->
        {:reply, resp, state}
    end
  end

  def handle_call(:get_users, _from, %{users: users} = state) do
    {:reply, users, state}
  end

  def get_users() do
    GenServer.call(__MODULE__, :get_users)
  end

  defp create_users(attrs, []), do: Enum.map(attrs, &create_user/1)

  # -> probably use a mapset..
  defp create_users(attrs, existing) do
    refs = for %{ref: ref} <- existing, do: ref

    attrs
    |> Enum.map(
      &(Enum.member?(refs, &1)
        |> case do
          false ->
            create_user(&1)

          _ ->
            []
        end)
    )
    |> List.flatten()
    |> Kernel.++(existing)
  end

  defp create_user(attr), do: %{currency: "USD", amount: 100_000, ref: attr}

  defp place_bet(
         %{user: user, amount: _amount, request_uuid: request_uuid, currency: currency} =
           bet_attrs,
         %{users: users} = state
       ) do
    with [%{amount: _amount, currency: _currency, ref: _ref} = user_map] <-
           Enum.filter(users, &(&1.ref == user)),
         :ok <- check_transaction(bet_attrs, state, user_map),
         {:ok, %{user: %{amount: updated_balance}, users: updated_users}} <-
           update_user_state(user_map, users, bet_attrs, operation: :debit) do
      {:ok,
       %{
         user: user,
         status: "RS_OK",
         request_uuid: request_uuid,
         currency: currency,
         balance: updated_balance
       }, updated_users}
    else
      {:error, %{status: :not_enough_money, balance: previous_balance}} ->
        {:error,
         %{
           user: user,
           status: "RS_ERROR_NOT_ENOUGH_MONEY",
           request_uuid: request_uuid,
           currency: currency,
           balance: previous_balance
         }}

      {:error, %{status: :bad_currency, balance: previous_balance}} ->
        {:error,
         %{
           user: user,
           status: "RS_ERROR_WRONG_CURRENCY",
           request_uuid: request_uuid,
           currency: currency,
           balance: previous_balance
         }}

      {:error, %{status: :duplicate, balance: previous_balance}} ->
        {:error,
         %{
           user: user,
           status: "RS_ERROR_DUPLICATE_TRANSACTION",
           request_uuid: request_uuid,
           currency: currency,
           balance: previous_balance
         }}

      _error ->
        {:error,
         %{
           user: user,
           status: "RS_ERROR_UNKNOWN",
           request_uuid: request_uuid,
           currency: currency,
           balance: 0
         }}
    end
  end

  defp process_win(
         %{user: user, currency: currency, request_uuid: request_uuid} = win_attrs,
         %{users: users} = state
       ) do
    with [user_map] <- Enum.filter(users, &(&1.ref == user)),
         :ok <- check_win(win_attrs, state, user_map),
         {:ok, %{user: %{amount: updated_balance}, users: updated_users}} <-
           update_user_state(user_map, users, win_attrs, operation: :credit) do
      {:ok,
       %{
         user: user,
         status: "RS_OK",
         request_uuid: request_uuid,
         currency: currency,
         balance: updated_balance
       }, updated_users}
    else
      {:error, %{status: :not_found, balance: previous_balance}} ->
        {:error,
         %{
           user: user,
           status: "RS_ERROR_TRANSACTION_DOES_NOT_EXIST",
           request_uuid: request_uuid,
           currency: currency,
           balance: previous_balance
         }}

      {:error, %{status: :claimed, balance: previous_balance}} ->
        {:error,
         %{
           user: user,
           status: "RS_ERROR_DUPLICATE_TRANSACTION",
           request_uuid: request_uuid,
           currency: currency,
           balance: previous_balance
         }}
    end
  end

  defp update_user_state(
         %{amount: previous_balance},
         _users,
         %{amount: bet_amount},
         operation: :debit
       )
       when bet_amount > previous_balance,
       do: {:error, %{status: :not_enough_money, balance: previous_balance}}

  defp update_user_state(
         %{ref: ref, amount: previous_balance} = user_map,
         users,
         %{amount: bet_amount},
         opts
       ) do
    current_balance =
      Keyword.get(opts, :operation)
      |> case do
        :debit -> previous_balance - bet_amount
        :credit -> previous_balance + bet_amount
      end

    updated_user = %{user_map | amount: current_balance}

    updated_users =
      users
      |> Enum.reject(&(&1.ref == ref))
      |> Kernel.++([updated_user])

    {:ok, %{user: updated_user, users: updated_users}}
  end

  defp check_transaction(
         %{currency: bet_currency},
         _,
         %{amount: previous_balance, currency: wallet_currency}
       )
       when bet_currency != wallet_currency,
       do: {:error, %{status: :bad_currency, balance: previous_balance}}

  defp check_transaction(
         %{transaction_uuid: transaction_uuid},
         %{bets: bets},
         %{amount: previous_balance}
       ) do
    Enum.filter(bets, &(&1.transaction_uuid == transaction_uuid))
    |> case do
      [_exists | _] -> {:error, %{status: :duplicate, balance: previous_balance}}
      _ -> :ok
    end
  end

  defp check_win(
         %{reference_transaction_uuid: reference_transaction_uuid} = win_attrs,
         %{wins: wins, bets: bets},
         %{
           amount: previous_balance
         } = user_map
       ) do
    Enum.filter(bets, &(&1.transaction_uuid == reference_transaction_uuid))
    |> case do
      [_exists | _] ->
        check_existing_win(win_attrs, wins, user_map)

      _ ->
        {:error, %{status: :not_found, balance: previous_balance}}
    end
  end

  defp check_existing_win(%{transaction_uuid: transaction_uuid}, wins, %{
         amount: previous_balance
       }) do
    Enum.filter(wins, &(&1.transaction_uuid == transaction_uuid))
    |> case do
      [_exists | _] -> {:error, %{status: :claimed, balance: previous_balance}}
      _ -> :ok
    end
  end
end

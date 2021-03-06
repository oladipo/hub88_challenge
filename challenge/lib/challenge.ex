defmodule Challenge do
  @moduledoc """
  Documentation for `Challenge`.
  """
  @doc """
  Start a linked and isolated supervision tree and returns the root server that
  will handle the requests.
  """
  @spec start :: GenServer.server()
  def start() do
    children = [
      Challenge.DynamicSupervisor
    ]

    opts = [strategy: :one_for_one, name: Challenge.Supervisor]

    {:ok, _} = Supervisor.start_link(children, opts)

    {:ok, pid} = Challenge.DynamicSupervisor.start_worker(:worker_1)

    pid
  end

  @doc """
  Create non-existing users with currency as "USD" and amount as 100_000.

  It ignores any entry that is NOT a non-empty binary or if the user already exists.
  """
  @spec create_users(server :: GenServer.server(), users :: [String.t()]) :: :ok
  def create_users(_server, []), do: :ok

  def create_users(server, users) do
    GenServer.cast(server, {:create_users, users})
  end

  @doc """
  The same behavior from `POST /transaction/bet` docs.

  The `body` parameter is the "body" from the docs as a map with keys as atoms.
  The result is the "response" from the docs as a map with keys as atoms.
  """
  @spec bet(server :: GenServer.server(), body :: map) :: map
  def bet(server, %{user: _user, amount: _amount, request_uuid: _request_uuid} = body) do
    with :ok <- validate_bet_params(body) do
      GenServer.call(server, {:bet, body})
    else
      _ ->
        %{
          user: nil,
          status: "RS_ERROR_WRONG_TYPES",
          request_uuid: nil,
          currency: nil,
          balance: nil
        }
    end
  end

  def bet(_server, _),
    do: %{
      user: nil,
      status: "RS_ERROR_WRONG_TYPES",
      request_uuid: nil,
      currency: nil,
      balance: nil
    }

  @doc """
  The same behavior from `POST /transaction/win` docs.

  The `body` parameter is the "body" from the docs as a map with keys as atoms.
  The result is the "response" from the docs as a map with keys as atoms.
  """
  @spec win(server :: GenServer.server(), body :: map) :: map
  def win(server, %{user: _user, amount: _amount, request_uuid: _request_uuid} = body) do
    with :ok <- validate_win_params(body) do
      GenServer.call(server, {:win, body})
    else
      _ ->
        %{
          user: nil,
          status: "RS_ERROR_WRONG_TYPES",
          request_uuid: nil,
          currency: nil,
          balance: nil
        }
    end
  end

  def win(_server, _),
    do: %{
      user: nil,
      status: "RS_ERROR_WRONG_TYPES",
      request_uuid: nil,
      currency: nil,
      balance: nil
    }

  defp validate_bet_params(%{user: user, amount: amount, request_uuid: request_uuid}) do
    with true <- validate_user(user),
         true <- validate_request_uuid(request_uuid),
         true <- validate_amount(amount) do
      :ok
    else
      _ -> {:error, :invalid}
    end
  end

  defp validate_win_params(%{user: user, amount: amount, request_uuid: request_uuid}) do
    with true <- validate_user(user),
         true <- validate_request_uuid(request_uuid),
         true <- validate_amount(amount) do
      :ok
    else
      _ -> {:error, :invalid}
    end
  end

  defp validate_user(param), do: String.length(param) > 0
  defp validate_request_uuid(param), do: String.length(param) > 0
  defp validate_amount(amount), do: is_integer(amount)
end

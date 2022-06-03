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
    {:ok, pid} = GenServer.start_link(Challenge.Worker, [])

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
    GenServer.call(server, {:bet, body})
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
    GenServer.call(server, {:win, body})
  end

  def win(_server, _),
    do: %{
      user: nil,
      status: "RS_ERROR_WRONG_TYPES",
      request_uuid: nil,
      currency: nil,
      balance: nil
    }
end

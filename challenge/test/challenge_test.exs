defmodule ChallengeTest do
  use ExUnit.Case
  doctest Challenge

  test "start/0 returns a gen server" do
    server_pid = Challenge.start()
    assert is_pid(server_pid)
  end

  describe "create_users/2" do
    test "can create users" do
      server_pid = Challenge.start()

      users =
        for _ <- 1..10 do
          Faker.UUID.v4()
        end

      assert :ok = Challenge.create_users(server_pid, users)
      created_users = GenServer.call(server_pid, :get_users)

      refute Enum.empty?(created_users)
      assert 10 == Enum.count(created_users)
    end

    test "does not create duplicates" do
      server_pid = Challenge.start()

      user_list =
        for _ <- 1..10 do
          Faker.UUID.v4()
        end

      duplicates = Enum.take(user_list, 2)

      assert :ok = Challenge.create_users(server_pid, user_list)
      created_users = GenServer.call(server_pid, :get_users)

      assert :ok = Challenge.create_users(server_pid, duplicates)

      assert created_users == GenServer.call(server_pid, :get_users)
    end

    test "can create new with existing" do
      server_pid = Challenge.start()

      user_list =
        for _ <- 1..10 do
          Faker.UUID.v4()
        end

      new_user_list =
        for _ <- 1..5 do
          Faker.UUID.v4()
        end

      assert :ok = Challenge.create_users(server_pid, user_list)
      assert :ok = Challenge.create_users(server_pid, new_user_list)

      all_users = GenServer.call(server_pid, :get_users)

      assert 15 == Enum.count(all_users)
    end
  end

  describe "bet/2" do
    setup do
      amount = Faker.Random.Elixir.random_between(10_000, 99_999)
      user = "#{Faker.Person.first_name()}#{Faker.Random.Elixir.random_between(1_000, 9_999)}"
      request_uuid = Faker.UUID.v4()
      currency = "USD"

      bet_attrs = %{
        user: user,
        transaction_uuid: Faker.UUID.v4(),
        supplier_transaction_id: Faker.UUID.v4(),
        token: Faker.UUID.v4(),
        supplier_user:
          "#{to_string(Faker.Lorem.characters(2))}_#{Faker.Random.Elixir.random_between(1_000, 9_999)}",
        round_closed: true,
        round: to_string(Faker.Lorem.characters(15)),
        reward_uuid: Faker.UUID.v4(),
        request_uuid: request_uuid,
        is_free: false,
        is_aggregated: false,
        game_code: "clt_#{Faker.App.name()}",
        currency: currency,
        bet: "zero",
        amount: amount,
        meta: %{
          selection: Faker.Team.name(),
          odds: 2.5
        }
      }

      {:ok, bet_attrs: bet_attrs}
    end

    test "returns valid response", %{
      bet_attrs:
        %{user: user, amount: amount, request_uuid: request_uuid, currency: currency} = bet_attrs
    } do
      server_pid = Challenge.start()
      :ok = Challenge.create_users(server_pid, [user])
      expected_balance = 100_000 - amount

      assert %{
               user: ^user,
               status: "RS_OK",
               request_uuid: ^request_uuid,
               currency: ^currency,
               balance: ^expected_balance
             } = Challenge.bet(server_pid, bet_attrs)
    end

    test "returns error response when user does not exist", %{
      bet_attrs: %{user: user, request_uuid: request_uuid, currency: currency} = bet_attrs
    } do
      server_pid = Challenge.start()
      users = for _ <- 1..5, do: Faker.Person.first_name()

      :ok = Challenge.create_users(server_pid, users)

      assert %{
               user: ^user,
               status: "RS_ERROR_UNKNOWN",
               request_uuid: ^request_uuid,
               currency: ^currency,
               balance: 0
             } = Challenge.bet(server_pid, bet_attrs)
    end

    test "returns error response with insufficient balance", %{
      bet_attrs: %{user: user, request_uuid: request_uuid, currency: currency} = bet_attrs
    } do
      server_pid = Challenge.start()
      :ok = Challenge.create_users(server_pid, [user])

      bet_attrs_1 =
        bet_attrs
        |> Map.update!(:amount, fn _ -> 70_000 end)
        |> Map.update!(:transaction_uuid, fn _ -> Faker.UUID.v4() end)

      bet_attrs_2 =
        bet_attrs
        |> Map.update!(:amount, fn _ -> 70_000 end)
        |> Map.update!(:transaction_uuid, fn _ -> Faker.UUID.v4() end)

      assert %{
               user: ^user,
               status: "RS_OK",
               request_uuid: ^request_uuid,
               currency: ^currency,
               balance: 30_000
             } = Challenge.bet(server_pid, bet_attrs_1)

      assert %{
               user: ^user,
               status: "RS_ERROR_NOT_ENOUGH_MONEY",
               request_uuid: ^request_uuid,
               currency: ^currency,
               balance: 30_000
             } = Challenge.bet(server_pid, bet_attrs_2)
    end

    test "returns error response with duplicate transaction uuid", %{
      bet_attrs: %{user: user, request_uuid: request_uuid, currency: currency} = bet_attrs
    } do
      server_pid = Challenge.start()
      :ok = Challenge.create_users(server_pid, [user])

      assert %{
               user: ^user,
               status: "RS_OK",
               request_uuid: ^request_uuid,
               currency: ^currency,
               balance: _balance
             } = Challenge.bet(server_pid, bet_attrs)

      assert %{
               user: ^user,
               status: "RS_ERROR_DUPLICATE_TRANSACTION",
               request_uuid: ^request_uuid,
               currency: ^currency,
               balance: _balance
             } = Challenge.bet(server_pid, bet_attrs)
    end

    test "returns error response with mismatching wallet currency  uuid", %{
      bet_attrs: %{user: user, request_uuid: request_uuid} = bet_attrs
    } do
      server_pid = Challenge.start()
      :ok = Challenge.create_users(server_pid, [user])

      bet_attrs_1 =
        bet_attrs
        |> Map.update!(:currency, fn _ -> "EUR" end)

      assert %{
               user: ^user,
               status: "RS_ERROR_WRONG_CURRENCY",
               request_uuid: ^request_uuid,
               currency: _currency,
               balance: _balance
             } = Challenge.bet(server_pid, bet_attrs_1)
    end

    test "returns error with invalid bet request" do
      server_pid = Challenge.start()

      assert %{
               user: _user,
               status: "RS_ERROR_WRONG_TYPES",
               request_uuid: _request_uuid,
               currency: _currency,
               balance: _balance
             } = Challenge.bet(server_pid, %{})

      assert %{
               user: _user,
               status: "RS_ERROR_WRONG_TYPES",
               request_uuid: _request_uuid,
               currency: _currency,
               balance: _balance
             } = Challenge.bet(server_pid, %{user: "", amount: 403.9, request_uuid: ""})
    end
  end

  describe "win/2" do
    setup do
      amount = Faker.Random.Elixir.random_between(10_000, 99_999)
      user = "#{Faker.Person.first_name()}#{Faker.Random.Elixir.random_between(1_000, 9_999)}"
      request_uuid = Faker.UUID.v4()
      transaction_uuid = Faker.UUID.v4()
      currency = "USD"

      bet_attrs = %{
        user: user,
        transaction_uuid: transaction_uuid,
        supplier_transaction_id: Faker.UUID.v4(),
        token: Faker.UUID.v4(),
        supplier_user:
          "#{to_string(Faker.Lorem.characters(2))}_#{Faker.Random.Elixir.random_between(1_000, 9_999)}",
        round_closed: true,
        round: to_string(Faker.Lorem.characters(15)),
        reward_uuid: Faker.UUID.v4(),
        request_uuid: request_uuid,
        is_free: false,
        is_aggregated: false,
        game_code: "clt_#{Faker.App.name()}",
        currency: currency,
        bet: "zero",
        amount: amount,
        meta: %{
          selection: Faker.Team.name(),
          odds: 2.5
        }
      }

      win_attrs = %{
        user: user,
        transaction_uuid: Faker.UUID.v4(),
        supplier_transaction_id: Faker.UUID.v4(),
        token: Faker.UUID.v4(),
        supplier_user:
          "#{to_string(Faker.Lorem.characters(2))}_#{Faker.Random.Elixir.random_between(1_000, 9_999)}",
        round_closed: true,
        round: to_string(Faker.Lorem.characters(15)),
        reward_uuid: Faker.UUID.v4(),
        request_uuid: request_uuid,
        reference_transaction_uuid: transaction_uuid,
        is_free: false,
        is_aggregated: false,
        game_code: "clt_#{Faker.App.name()}",
        currency: "USD",
        bet: "zero",
        amount: amount,
        meta: %{
          selection: Faker.Team.name(),
          odds: 2.5
        }
      }

      {:ok,
       currency: currency,
       request_uuid: request_uuid,
       amount: amount,
       user: user,
       win_attrs: win_attrs,
       bet_attrs: bet_attrs}
    end

    @tag :focus
    test "returns valid response", %{
      user: user,
      request_uuid: request_uuid,
      win_attrs: %{amount: win_amount} = win_attrs,
      bet_attrs: %{amount: bet_amount} = bet_attrs
    } do
      server_pid = Challenge.start()
      :ok = Challenge.create_users(server_pid, [user])

      expected_balance = 100_000 - bet_amount + win_amount

      assert %{
               user: ^user,
               status: "RS_OK",
               request_uuid: ^request_uuid,
               currency: _currency,
               balance: _balance
             } = Challenge.bet(server_pid, bet_attrs)

      assert %{
               user: ^user,
               status: "RS_OK",
               request_uuid: ^request_uuid,
               currency: _currency,
               balance: ^expected_balance
             } = Challenge.win(server_pid, win_attrs)
    end

    test "returns error when previous bet does not exist", %{
      user: user,
      currency: currency,
      request_uuid: request_uuid,
      win_attrs: win_attrs
    } do
      server_pid = Challenge.start()
      :ok = Challenge.create_users(server_pid, [user])

      expected_balance = 100_000

      assert %{
               user: ^user,
               status: "RS_ERROR_TRANSACTION_DOES_NOT_EXIST",
               request_uuid: ^request_uuid,
               currency: ^currency,
               balance: ^expected_balance
             } = Challenge.win(server_pid, win_attrs)
    end

    test "returns error when win has been previously processed", %{
      user: user,
      currency: currency,
      request_uuid: request_uuid,
      win_attrs: win_attrs,
      bet_attrs: bet_attrs
    } do
      server_pid = Challenge.start()
      :ok = Challenge.create_users(server_pid, [user])

      assert %{
               user: ^user,
               status: "RS_OK",
               request_uuid: ^request_uuid,
               currency: _currency,
               balance: _balance
             } = Challenge.bet(server_pid, bet_attrs)

      assert %{
               user: ^user,
               status: "RS_OK",
               request_uuid: ^request_uuid,
               currency: ^currency,
               balance: _balance
             } = Challenge.win(server_pid, win_attrs)

      assert %{
               user: ^user,
               status: "RS_ERROR_DUPLICATE_TRANSACTION",
               request_uuid: ^request_uuid,
               currency: ^currency,
               balance: _balance
             } = Challenge.win(server_pid, win_attrs)
    end

    test "returns error with invalid win request" do
      server_pid = Challenge.start()

      assert %{
               user: _user,
               status: "RS_ERROR_WRONG_TYPES",
               request_uuid: _request_uuid,
               currency: _currency,
               balance: _balance
             } = Challenge.win(server_pid, %{})

      assert %{
               user: _user,
               status: "RS_ERROR_WRONG_TYPES",
               request_uuid: _request_uuid,
               currency: _currency,
               balance: _balance
             } = Challenge.win(server_pid, %{user: "", amount: 403.9, request_uuid: ""})
    end
  end
end

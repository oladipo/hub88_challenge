defmodule Challenge.DynamicSupervisor do
  use DynamicSupervisor

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  def start_worker(worker_id) do
    DynamicSupervisor.start_child(__MODULE__, {Challenge.Worker, worker_id})
  end

  def stop_worker(worker_id) do
    DynamicSupervisor.terminate_child(__MODULE__, worker_id)
  end
end

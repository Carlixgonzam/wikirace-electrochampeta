defmodule Player.Application do
  @moduledoc """
  Boots this node with no crawler running yet.

  Replace this however your design needs: add your own
  `DynamicSupervisor`, `Task.Supervisor`, whatever your crawler's
  supervision tree looks like. The harness only ever talks to a module that
  declares `@behaviour WikiRace.Crawler`; nothing here needs to stay.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = []

    Supervisor.start_link(children, strategy: :one_for_one, name: Player.Supervisor)
  end
end

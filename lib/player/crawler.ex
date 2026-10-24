defmodule Player.Crawler do
  @moduledoc """
  Your crawler.

  The harness calls `start/2` and `status/1` of this module. Both raise until you
  implement them. `WikiRace.Crawler` describes what each one must do.
  """

  @behaviour WikiRace.Crawler

  @impl WikiRace.Crawler
  def start(inicio, objetivo) do
    case Process.whereis(Player.Search) do
      nil -> :ok
      pid -> parar(pid)
    end

    DynamicSupervisor.start_child(Player.RaceSupervisor, {Player.Search, {inicio, objetivo}})
  end

  @impl WikiRace.Crawler
  def status(_pid) do
    Player.Search.status()
  end

  defp parar(pid) do
    ref = Process.monitor(pid)
    Process.exit(pid, :kill)

    receive do
      {:DOWN, ^ref, :process, _, _} -> :ok
    end
  end
end

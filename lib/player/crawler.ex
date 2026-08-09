defmodule Player.Crawler do
  @moduledoc """
  Where your crawler goes.

  This module already declares `@behaviour WikiRace.Crawler`, so it compiles
  and the harness can discover it, but both callbacks just raise. Replace
  them with a real implementation; see `WikiRace.Crawler`'s docs for the
  contract and `player/README.md` for how to run the test that checks you did.
  """

  @behaviour WikiRace.Crawler

  @impl WikiRace.Crawler
  def start(_start_url, _target_url) do
    raise "TODO: implement WikiRace.Crawler.start/2"
  end

  @impl WikiRace.Crawler
  def status(_pid) do
    raise "TODO: implement WikiRace.Crawler.status/1"
  end
end

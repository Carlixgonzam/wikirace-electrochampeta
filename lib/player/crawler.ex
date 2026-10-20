defmodule Player.Crawler do
  @moduledoc """
  Your crawler.

  The harness calls `start/2` and `status/1` of this module. Both raise until you
  implement them. `WikiRace.Crawler` describes what each one must do.
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

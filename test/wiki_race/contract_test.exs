defmodule Player.ContractTest do
  @moduledoc """
  Fails until `Player.Crawler` implements `WikiRace.Crawler` for real.

  This is the same check the harness performs on race day: `start/2` must
  return a monitorable pid, and `status/1` must return a `WikiRace.Status`.
  Nothing here is graded directly, it just tells you locally whether the
  harness would be able to talk to your crawler at all.
  """
  use ExUnit.Case, async: true

  alias WikiRace.Status

  test "start/2 returns a monitorable pid" do
    assert {:ok, pid} =
             Player.Crawler.start("http://kiwix/A/Chess", "http://kiwix/A/Bee")

    assert is_pid(pid)
    assert Process.alive?(pid)
  end

  test "status/1 returns a WikiRace.Status" do
    {:ok, pid} = Player.Crawler.start("http://kiwix/A/Chess", "http://kiwix/A/Bee")

    assert %Status{} = Player.Crawler.status(pid)
  end
end

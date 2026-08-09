defmodule WikiRace.Harness do
  @moduledoc """
  Client for reporting results back to the competition harness.

  This module ships with the platform and is the only way your crawler should
  talk to the harness. It hides where the harness lives and how it is
  addressed, so that addressing can change without breaking your code.

  Call `report/1` from anywhere in your crawler, any process and any node in
  your cluster, the instant you have a path.
  """

  @registered_name :wiki_race_harness

  @doc """
  Reports a completed path to the harness.

  `path` is the list of article URLs walked from the start article to the
  target, including both endpoints.

  Fire-and-forget: this returns `:ok` immediately and never blocks your crawl,
  even if the harness is unreachable. The harness stamps the arrival time
  against its own clock. Timestamps generated on your node are not comparable
  to it, which is why this function deliberately doesn't send one.

  Reporting more than once is fine and expected: report a valid path as soon as
  you have one, and report again if you find a shorter one. The harness keeps
  the shortest path per node, with the arrival time of the report that
  established it.
  """
  @spec report(WikiRace.Status.path()) :: :ok
  def report(path) when is_list(path) do
    send_to_harness({:path_found, self(), path})
  end

  @doc """
  Tells the harness your crawler has exhausted its search without finding a
  path.

  Optional, the race ends for you at the time limit regardless. Sending this
  lets the dashboard show you as finished rather than still running, and lets a
  race end early once both crawlers have settled.
  """
  @spec report_exhausted() :: :ok
  def report_exhausted do
    send_to_harness({:exhausted, self()})
  end

  @doc """
  The name the harness process is registered under, for debugging.

  You should not need this, use `report/1`. It is exposed so you can check
  connectivity from a remote IEx session:

      iex> :global.whereis_name(WikiRace.Harness.registered_name())
      #PID<12345.678.0>
  """
  @spec registered_name() :: atom()
  def registered_name, do: @registered_name

  defp send_to_harness(message) do
    case :global.whereis_name(@registered_name) do
      :undefined -> :ok
      pid -> send(pid, message) && :ok
    end
  end
end

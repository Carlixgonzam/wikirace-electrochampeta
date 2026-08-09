defmodule WikiRace.Status do
  @moduledoc """
  A snapshot of a crawler's progress, returned by `c:WikiRace.Crawler.status/1`.

  The harness polls `status/1` on a tick and renders these fields on the live
  dashboard. Build it with `new/1` so a misspelled key fails immediately rather
  than showing up as a blank column mid-race:

      WikiRace.Status.new(
        current_url: url,
        frontier_size: :queue.len(frontier),
        visited_count: map_size(visited),
        state: :running
      )

  Every field has a default, so a partially-populated status is still valid,
  but `frontier_size`, `visited_count` and `state` are what make the dashboard
  interesting to watch, so keep them current.
  """

  @typedoc "Where the crawler is in its search."
  @type state :: :running | :found | :exhausted

  @typedoc """
  A path from the start article to the target, as the list of URLs walked.
  Includes both endpoints, so a start article that *is* the target is a path of
  length 1. `[]` means no path found yet.
  """
  @type path :: [String.t()]

  @type t :: %__MODULE__{
          current_url: String.t() | nil,
          frontier_size: non_neg_integer(),
          visited_count: non_neg_integer(),
          path: path(),
          state: state()
        }

  defstruct current_url: nil,
            frontier_size: 0,
            visited_count: 0,
            path: [],
            state: :running

  @doc """
  Builds a status from a keyword list or map, raising on unknown keys.
  """
  @spec new(Enumerable.t()) :: t()
  def new(fields \\ []), do: struct!(__MODULE__, fields)
end

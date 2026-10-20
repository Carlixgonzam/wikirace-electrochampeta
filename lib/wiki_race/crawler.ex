defmodule WikiRace.Crawler do
  @moduledoc """
  The contract every group's crawler must implement.

  This is the entire surface the competition harness touches. Implement it in
  your own OTP application and the harness can deploy, start, observe and score
  your crawler without knowing anything else about your design.

      defmodule MyGroup.Crawler do
        @behaviour WikiRace.Crawler

        @impl true
        def start(start_url, target_url) do
          DynamicSupervisor.start_child(
            MyGroup.CrawlerSupervisor,
            {MyGroup.Search, {start_url, target_url}}
          )
        end

        @impl true
        def status(pid), do: GenServer.call(pid, :status)
      end

  ## Lifecycle

  The pid returned by `c:start/2` lives in **your** supervision tree. The
  harness never supervises it. It only `Process.monitor/1`s the pid, so if your
  crawler crashes the harness records a `:DOWN` and the race continues without
  you. Designing that supervision tree is part of the assignment.

  When the time limit expires the harness takes one final `c:status/1` snapshot
  and then kills the pid outright. There is no shutdown callback and no
  cooperative deadline to check, so do not rely on running any cleanup.

  ## Finding a path

  `c:status/1` polling drives the dashboard, but it does **not** decide the
  race. The moment you find a path, call `WikiRace.Harness.report/1`:

      WikiRace.Harness.report([start_url, ..., target_url])

  The harness timestamps that message on arrival, and that timestamp is your
  wall-clock result, the tiebreaker between crawlers that found paths of equal
  length. Report as early as you can, then keep searching if you think you can
  do better: later reports from the same node supersede earlier ones, so it is
  safe to report a valid path immediately and improve on it.

  Also set `path` and `state: :found` in your `c:status/1` snapshots, so a
  missed report still shows up on the dashboard.

  ## URLs

  Both arguments to `c:start/2` are complete, fetchable URLs pointing at the
  local Kiwix instance, so pass them straight to `Req.get/1`, no construction
  needed. Never request `wikipedia.org`; the offline snapshot is the only
  legal source, and hammering the public internet in parallel will get the
  competition network blocked.

  Links you extract from a page with Floki will be relative. Resolve them
  against the page you fetched them from, and stay inside the article
  namespace. Kiwix serves search pages, category listings and static assets
  from the same host, and following those wastes the race.
  """

  @doc """
  Starts a crawl from `start_url` toward `target_url`.

  Returns the pid of the process the harness should monitor and poll. That
  process must be supervised by your own application. Return `{:error, reason}`
  if the crawler cannot start at all; `reason` is shown on the dashboard.

  Both URLs are absolute Kiwix article URLs. This is called once per race, and
  it must return promptly, so start your workers and return, don't crawl inline.
  """
  @callback start(start_url :: String.t(), target_url :: String.t()) ::
              {:ok, pid()} | {:error, term()}

  @doc """
  Returns a snapshot of the crawl's current progress.

  Polled frequently (roughly every 250ms) for the whole race, on the harness's
  schedule. Keep it cheap and non-blocking: read from ETS or from a GenServer
  that isn't also doing the crawling. If this call blocks or times out the
  dashboard goes blank, and if it blocks past the time limit you lose the final
  snapshot that would have been scored.
  """
  @callback status(pid :: pid()) :: WikiRace.Status.t()
end

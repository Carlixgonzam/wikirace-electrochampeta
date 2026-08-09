# Compose/dev tooling, not part of the crawler assignment: connects this
# node to the platform node by explicit Node.connect/1, the same manual step
# RUNNING.md's non-compose flow does by hand, just scripted and retried since
# container start order isn't the same as "the platform's app has booted."
#
# Invoked as: elixir --name ... --cookie ... -S mix run --no-halt bin/connect.exs

platform_node = System.fetch_env!("PLATFORM_NODE") |> String.to_atom()

connected? =
  Enum.reduce_while(1..30, false, fn attempt, _acc ->
    case Node.connect(platform_node) do
      true ->
        {:halt, true}

      _ ->
        IO.puts("waiting for #{platform_node} (attempt #{attempt}/30)")
        Process.sleep(1_000)
        {:cont, false}
    end
  end)

if connected? do
  IO.puts("connected to #{platform_node}")
else
  IO.puts("could not connect to #{platform_node} after 30s, staying up anyway")
end

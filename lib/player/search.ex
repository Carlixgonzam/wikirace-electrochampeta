defmodule Player.Search do
  use GenServer, restart: :temporary

  alias Player.Links
  alias WikiRace.Harness
  alias WikiRace.Status

  @tabla :race_status
  @bloque 32

  def start_link({inicio, objetivo}) do
    GenServer.start_link(__MODULE__, {inicio, objetivo}, name: __MODULE__)
  end

  def status do
    try do
      Status.new(
        current_url: leer(:actual),
        frontier_size: leer(:frontera),
        visited_count: leer(:visitados),
        path: leer(:camino),
        state: leer(:estado)
      )
    rescue
      ArgumentError -> Status.new()
    end
  end

  def init({inicio, objetivo}) do
    :ets.new(@tabla, [:named_table, :set])

    :ets.insert(@tabla, [
      {:estado, :running},
      {:camino, []},
      {:visitados, 0},
      {:frontera, 1},
      {:actual, inicio}
    ])

    carrera = %{
      objetivo: Links.clave(objetivo),
      url_objetivo: objetivo,
      prefijo: Links.prefijo(inicio)
    }

    send(self(), {:buscar, inicio})
    {:ok, carrera}
  end

  def handle_info({:buscar, inicio}, carrera) do
    clave = Links.clave(inicio)

    if clave == carrera.objetivo do
      terminar()
    else
      buscar([[inicio]], %{clave => true}, carrera)
    end

    {:noreply, carrera}
  end

  defp leer(clave) do
    [{_, valor}] = :ets.lookup(@tabla, clave)
    valor
  end

  defp terminar do
    Harness.report_exhausted()
    :ets.insert(@tabla, {:estado, :exhausted})
  end

  defp buscar([], _vistos, _carrera), do: terminar()

  defp buscar(nivel, vistos, carrera) do
    :ets.insert(@tabla, {:frontera, length(nivel)})

    case explorar(Enum.chunk_every(nivel, @bloque), vistos, [], carrera) do
      {:encontrado, camino} ->
        Harness.report(camino)
        :ets.insert(@tabla, [{:camino, camino}, {:estado, :found}])

      {:siguiente, siguiente, vistos} ->
        buscar(siguiente, vistos, carrera)
    end
  end

  defp explorar([], vistos, siguiente, _carrera), do: {:siguiente, siguiente, vistos}

  defp explorar([bloque | resto], vistos, siguiente, carrera) do
    [[url | _] | _] = bloque
    :ets.insert(@tabla, {:actual, url})

    resultados =
      bloque
      |> Enum.map(&Task.async(fn -> visitar(&1, carrera) end))
      |> Enum.map(&Task.await(&1, 10_000))

    contar(resultados)

    case Enum.find(resultados, &match?({:encontrado, _}, &1)) do
      nil ->
        {siguiente, vistos} = Enum.reduce(resultados, {siguiente, vistos}, &agregar/2)
        explorar(resto, vistos, siguiente, carrera)

      encontrado ->
        encontrado
    end
  end

  defp visitar([url | _] = camino, carrera) do
    case Links.descargar(url) do
      {:ok, html} ->
        links = Links.extraer(html, url, carrera.prefijo)

        case Enum.find(links, fn {clave, _} -> clave == carrera.objetivo end) do
          nil -> {:links, camino, links}
          _ -> {:encontrado, Enum.reverse([carrera.url_objetivo | camino])}
        end

      :error ->
        :error
    end
  end

  defp contar(resultados) do
    n = Enum.count(resultados, &(&1 != :error))
    :ets.insert(@tabla, {:visitados, leer(:visitados) + n})
  end

  defp agregar(:error, acc), do: acc

  defp agregar({:links, camino, links}, acc) do
    Enum.reduce(links, acc, fn {clave, url}, {siguiente, vistos} ->
      if Map.has_key?(vistos, clave) do
        {siguiente, vistos}
      else
        {[[url | camino] | siguiente], Map.put(vistos, clave, true)}
      end
    end)
  end
end

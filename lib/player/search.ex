defmodule Player.Search do
  use GenServer, restart: :temporary

  alias Player.Links
  alias WikiRace.Harness
  alias WikiRace.Status

  @tabla :race_status
  @trabajadores 32

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

    clave = Links.clave(inicio)

    carrera = %{
      objetivo: Links.clave(objetivo),
      url_objetivo: objetivo,
      prefijo: Links.prefijo(inicio)
    }

    estado = %{
      carrera: carrera,
      actual: [[inicio]],
      siguiente: [],
      pendientes: 1,
      vistos: %{clave => true},
      libres: [],
      visitados: 0,
      listo: clave == carrera.objetivo
    }

    send(self(), :empezar)
    {:ok, estado}
  end

  def handle_info(:empezar, %{listo: true} = estado) do
    terminar()
    {:noreply, estado}
  end

  def handle_info(:empezar, estado) do
    yo = self()
    Enum.each(1..@trabajadores, fn _ -> spawn_link(fn -> trabajar(yo, estado.carrera) end) end)
    {:noreply, estado}
  end

  def handle_info({:pedir, pid}, %{listo: true} = estado) do
    send(pid, :parar)
    {:noreply, estado}
  end

  def handle_info({:pedir, pid}, estado) do
    {:noreply, repartir(%{estado | libres: [pid | estado.libres]})}
  end

  def handle_info({:links, camino, links}, %{listo: false} = estado) do
    {siguiente, vistos, nuevos} =
      Enum.reduce(links, {estado.siguiente, estado.vistos, 0}, &agregar(&1, &2, camino))

    estado = %{
      estado
      | siguiente: siguiente,
        vistos: vistos,
        pendientes: estado.pendientes + nuevos,
        visitados: estado.visitados + 1
    }

    :ets.insert(@tabla, [{:visitados, estado.visitados}, {:frontera, estado.pendientes}])
    {:noreply, estado}
  end

  def handle_info({:encontrado, camino}, %{listo: false} = estado) do
    Harness.report(camino)
    :ets.insert(@tabla, [{:camino, camino}, {:estado, :found}])
    Enum.each(estado.libres, &send(&1, :parar))
    {:noreply, %{estado | listo: true, libres: []}}
  end

  def handle_info(_mensaje, estado), do: {:noreply, estado}

  defp leer(clave) do
    [{_, valor}] = :ets.lookup(@tabla, clave)
    valor
  end

  defp terminar do
    Harness.report_exhausted()
    :ets.insert(@tabla, {:estado, :exhausted})
  end

  defp agregar({clave, url}, {siguiente, vistos, n}, camino) do
    if Map.has_key?(vistos, clave) do
      {siguiente, vistos, n}
    else
      {[[url | camino] | siguiente], Map.put(vistos, clave, true), n + 1}
    end
  end

  defp repartir(%{libres: []} = estado), do: estado

  defp repartir(%{actual: [], siguiente: []} = estado) do
    if length(estado.libres) == @trabajadores do
      terminar()
      Enum.each(estado.libres, &send(&1, :parar))
      %{estado | listo: true, libres: []}
    else
      estado
    end
  end

  defp repartir(%{actual: []} = estado) do
    repartir(%{estado | actual: estado.siguiente, siguiente: []})
  end

  defp repartir(%{actual: [[url | _] = camino | resto], libres: [pid | libres]} = estado) do
    send(pid, {:pagina, camino})
    :ets.insert(@tabla, {:actual, url})
    repartir(%{estado | actual: resto, libres: libres, pendientes: estado.pendientes - 1})
  end

  defp trabajar(coordinador, carrera) do
    send(coordinador, {:pedir, self()})

    receive do
      {:pagina, camino} ->
        send(coordinador, visitar(camino, carrera))
        trabajar(coordinador, carrera)

      :parar ->
        :ok
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
end

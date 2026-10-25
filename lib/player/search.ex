defmodule Player.Search do
  use GenServer, restart: :temporary

  alias Player.Links
  alias WikiRace.Harness
  alias WikiRace.Status

  @tabla :race_status
  @trabajadores 32
  @profundidad 2

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
      alta: [],
      actual: [[inicio]],
      siguiente: [],
      vecinos: nil,
      espera: [],
      pendientes: 1,
      vistos: %{clave => true},
      libres: [],
      turnos: System.schedulers_online(),
      fila: [],
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
    carrera = Map.put(estado.carrera, :coordinador, yo)
    spawn_link(fn -> send(yo, {:vecinos, vecinos(carrera)}) end)
    Enum.each(1..@trabajadores, fn _ -> spawn_link(fn -> trabajar(yo, carrera) end) end)
    {:noreply, estado}
  end

  def handle_info({:vecinos, vecinos}, estado) do
    estado =
      Enum.reduce(Enum.reverse(estado.espera), %{estado | vecinos: vecinos, espera: []}, fn
        {camino, links}, estado -> juntar(estado, camino, links)
      end)

    {:noreply, repartir(estado)}
  end

  def handle_info({:turno, pid}, %{turnos: 0} = estado) do
    {:noreply, %{estado | fila: estado.fila ++ [pid]}}
  end

  def handle_info({:turno, pid}, estado) do
    send(pid, :turno)
    {:noreply, %{estado | turnos: estado.turnos - 1}}
  end

  def handle_info(:soltar, %{fila: [pid | fila]} = estado) do
    send(pid, :turno)
    {:noreply, %{estado | fila: fila}}
  end

  def handle_info(:soltar, estado) do
    {:noreply, %{estado | turnos: estado.turnos + 1}}
  end

  def handle_info({:pedir, pid}, %{listo: true} = estado) do
    send(pid, :parar)
    {:noreply, estado}
  end

  def handle_info({:pedir, pid}, estado) do
    {:noreply, repartir(%{estado | libres: [pid | estado.libres]})}
  end

  def handle_info({:links, camino, links}, %{listo: false, vecinos: nil} = estado) do
    {:noreply, %{estado | espera: [{camino, links} | estado.espera]}}
  end

  def handle_info({:links, camino, links}, %{listo: false} = estado) do
    {:noreply, juntar(estado, camino, links)}
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

  defp juntar(estado, camino, links) do
    vecinos =
      if length(camino) <= @profundidad do
        estado.vecinos
      else
        %{}
      end

    {alta, siguiente, vistos, nuevos} =
      Enum.reduce(
        links,
        {[], estado.siguiente, estado.vistos, 0},
        &agregar(&1, &2, camino, vecinos)
      )

    estado = %{
      estado
      | alta: estado.alta ++ alta,
        siguiente: siguiente,
        vistos: vistos,
        pendientes: estado.pendientes + nuevos,
        visitados: estado.visitados + 1
    }

    :ets.insert(@tabla, [{:visitados, estado.visitados}, {:frontera, estado.pendientes}])
    estado
  end

  defp agregar({clave, url}, {alta, siguiente, vistos, n}, camino, vecinos) do
    cond do
      Map.has_key?(vistos, clave) ->
        {alta, siguiente, vistos, n}

      Map.has_key?(vecinos, clave) ->
        {[[url | camino] | alta], siguiente, Map.put(vistos, clave, true), n + 1}

      true ->
        {alta, [[url | camino] | siguiente], Map.put(vistos, clave, true), n + 1}
    end
  end

  defp repartir(%{libres: []} = estado), do: estado

  defp repartir(%{alta: [camino | resto]} = estado) do
    repartir(dar(%{estado | alta: resto}, camino))
  end

  defp repartir(%{vecinos: nil, actual: []} = estado), do: estado

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

  defp repartir(%{actual: [camino | resto]} = estado) do
    repartir(dar(%{estado | actual: resto}, camino))
  end

  defp dar(%{libres: [pid | libres]} = estado, [url | _] = camino) do
    send(pid, {:pagina, camino})
    :ets.insert(@tabla, {:actual, url})
    %{estado | libres: libres, pendientes: estado.pendientes - 1}
  end

  defp vecinos(carrera) do
    case Links.descargar(carrera.url_objetivo) do
      {:ok, html} ->
        html
        |> parsear(carrera.url_objetivo, carrera)
        |> Enum.reduce(%{}, fn {clave, _}, vecinos -> Map.put(vecinos, clave, true) end)

      :error ->
        %{}
    end
  end

  defp trabajar(coordinador, carrera) do
    send(coordinador, {:pedir, self()})

    receive do
      {:pagina, camino} ->
        send(coordinador, visitar_aparte(camino, carrera))
        trabajar(coordinador, carrera)

      :parar ->
        :ok
    end
  end

  defp visitar_aparte(camino, carrera) do
    yo = self()
    pid = spawn_link(fn -> send(yo, {self(), visitar(camino, carrera)}) end)

    receive do
      {^pid, resultado} -> resultado
    end
  end

  defp visitar([url | _] = camino, carrera) do
    case Links.descargar(url) do
      {:ok, html} ->
        links = parsear(html, url, carrera)

        case Enum.find(links, fn {clave, _} -> clave == carrera.objetivo end) do
          nil -> {:links, camino, links}
          _ -> {:encontrado, Enum.reverse([carrera.url_objetivo | camino])}
        end

      :error ->
        :error
    end
  end

  defp parsear(html, url, carrera) do
    send(carrera.coordinador, {:turno, self()})

    receive do
      :turno -> :ok
    end

    links = Links.extraer(html, url, carrera.prefijo)
    send(carrera.coordinador, :soltar)
    links
  end
end

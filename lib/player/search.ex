defmodule Player.Search do
  use GenServer, restart: :temporary

  alias Player.Links
  alias WikiRace.Harness
  alias WikiRace.Status

  @tabla :race_status
  @vistos :race_vistos
  @padres :race_padres
  @trabajadores 16
  @profundidad 25
  @frontera_max 250_000

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
    Process.flag(:trap_exit, true)
    :ets.new(@tabla, [:named_table, :set])
    :ets.new(@vistos, [:named_table, :set, :public])
    :ets.new(@padres, [:named_table, :set, :public])

    :ets.insert(@tabla, [
      {:estado, :running},
      {:camino, []},
      {:visitados, 0},
      {:frontera, 1},
      {:actual, inicio}
    ])

    clave = Links.clave(inicio)
    :ets.insert(@vistos, {clave, true})
    :ets.insert(@padres, {clave, {nil, inicio}})

    carrera = %{
      objetivo: Links.clave(objetivo),
      url_objetivo: objetivo,
      prefijo: Links.prefijo(inicio)
    }

    estado = %{
      carrera: carrera,
      alta: [],
      actual: [clave],
      siguiente: [],
      vecinos: nil,
      espera: [],
      pendientes: 1,
      libres: [],
      ocupados: %{},
      turnos: System.schedulers_online(),
      fila: [],
      parseando: [],
      lector: nil,
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
    {:ok, lector} = Task.start_link(fn -> send(yo, {:vecinos, vecinos(carrera)}) end)
    Enum.each(1..@trabajadores, fn _ -> Task.start_link(fn -> trabajar(yo, carrera) end) end)
    {:noreply, %{estado | carrera: carrera, lector: lector}}
  end

  def handle_info({:vecinos, vecinos}, estado) do
    estado =
      Enum.reduce(Enum.reverse(estado.espera), %{estado | vecinos: vecinos, espera: []}, fn
        {clave, links}, estado -> juntar(estado, clave, links)
      end)

    {:noreply, repartir(estado)}
  end

  def handle_info({:turno, pid}, %{turnos: 0} = estado) do
    {:noreply, %{estado | fila: estado.fila ++ [pid]}}
  end

  def handle_info({:turno, pid}, estado) do
    {:noreply, dar_turno(%{estado | turnos: estado.turnos - 1}, pid)}
  end

  def handle_info({:soltar, pid}, estado) do
    {:noreply, soltar(%{estado | parseando: List.delete(estado.parseando, pid)})}
  end

  def handle_info({:DOWN, _ref, :process, pid, _razon}, estado) do
    if Enum.member?(estado.parseando, pid) do
      {:noreply, soltar(%{estado | parseando: List.delete(estado.parseando, pid)})}
    else
      {:noreply, estado}
    end
  end

  def handle_info({:EXIT, _pid, :normal}, estado), do: {:noreply, estado}

  def handle_info({:EXIT, pid, _razon}, %{lector: pid, vecinos: nil} = estado) do
    handle_info({:vecinos, %{}}, estado)
  end

  def handle_info({:EXIT, pid, _razon}, %{lector: pid} = estado), do: {:noreply, estado}

  def handle_info({:EXIT, pid, _razon}, estado) do
    yo = self()
    Task.start_link(fn -> trabajar(yo, estado.carrera) end)
    estado = %{estado | libres: List.delete(estado.libres, pid)}

    case Map.fetch(estado.ocupados, pid) do
      {:ok, clave} ->
        {:noreply,
         repartir(%{
           estado
           | actual: [clave | estado.actual],
             pendientes: estado.pendientes + 1,
             ocupados: Map.delete(estado.ocupados, pid)
         })}

      :error ->
        {:noreply, estado}
    end
  end

  def handle_info({:pedir, pid}, %{listo: true} = estado) do
    send(pid, :parar)
    {:noreply, estado}
  end

  def handle_info({:pedir, pid}, estado) do
    {:noreply,
     repartir(%{
       estado
       | libres: [pid | estado.libres],
         ocupados: Map.delete(estado.ocupados, pid)
     })}
  end

  def handle_info({:links, clave, links}, %{listo: false, vecinos: nil} = estado) do
    {:noreply, %{estado | espera: [{clave, links} | estado.espera]}}
  end

  def handle_info({:links, clave, links}, %{listo: false} = estado) do
    {:noreply, juntar(estado, clave, links)}
  end

  def handle_info({:encontrado, clave}, %{listo: false} = estado) do
    camino = reconstruir(clave) ++ [estado.carrera.url_objetivo]
    Harness.report(camino)
    visitados = estado.visitados + 1
    :ets.insert(@tabla, [{:camino, camino}, {:visitados, visitados}, {:estado, :found}])
    Enum.each(estado.libres, &send(&1, :parar))
    {:noreply, %{estado | listo: true, libres: [], visitados: visitados}}
  end

  def handle_info({:fallo, clave}, %{listo: false} = estado) do
    {:noreply,
     %{estado | siguiente: [clave | estado.siguiente], pendientes: estado.pendientes + 1}}
  end

  def handle_info(_mensaje, estado), do: {:noreply, estado}

  defp leer(clave) do
    [{_, valor}] = :ets.lookup(@tabla, clave)
    valor
  end

  defp dar_turno(estado, pid) do
    send(pid, :turno)
    Process.monitor(pid)
    %{estado | parseando: [pid | estado.parseando]}
  end

  defp soltar(%{fila: [pid | fila]} = estado) do
    dar_turno(%{estado | fila: fila}, pid)
  end

  defp soltar(estado), do: %{estado | turnos: estado.turnos + 1}

  defp terminar do
    Harness.report_exhausted()
    :ets.insert(@tabla, {:estado, :exhausted})
  end

  defp juntar(estado, padre, links) do
    vecinos =
      if profundidad(padre) < @profundidad do
        estado.vecinos
      else
        %{}
      end

    espacio = @frontera_max - :ets.info(@vistos, :size)

    {alta, siguiente, nuevos, _espacio} =
      Enum.reduce(links, {[], estado.siguiente, 0, espacio}, &agregar(&1, &2, padre, vecinos))

    estado = %{
      estado
      | alta: estado.alta ++ alta,
        siguiente: siguiente,
        pendientes: estado.pendientes + nuevos,
        visitados: estado.visitados + 1
    }

    :ets.insert(@tabla, [{:visitados, estado.visitados}, {:frontera, estado.pendientes}])
    estado
  end

  defp agregar(_link, {alta, siguiente, n, 0}, _padre, _vecinos) do
    {alta, siguiente, n, 0}
  end

  defp agregar({clave, url}, {alta, siguiente, n, espacio}, padre, vecinos) do
    case :ets.insert_new(@vistos, {clave, true}) do
      true ->
        :ets.insert(@padres, {clave, {padre, url}})

        if Map.has_key?(vecinos, clave) do
          {[clave | alta], siguiente, n + 1, espacio - 1}
        else
          {alta, [clave | siguiente], n + 1, espacio - 1}
        end

      false ->
        {alta, siguiente, n, espacio}
    end
  end

  defp repartir(%{libres: []} = estado), do: estado

  defp repartir(%{alta: [clave | resto]} = estado) do
    repartir(dar(%{estado | alta: resto}, clave))
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

  defp repartir(%{actual: [clave | resto]} = estado) do
    repartir(dar(%{estado | actual: resto}, clave))
  end

  defp dar(%{libres: [pid | libres]} = estado, clave) do
    [{^clave, {_padre, url}}] = :ets.lookup(@padres, clave)
    send(pid, {:pagina, clave})
    :ets.insert(@tabla, {:actual, url})

    %{
      estado
      | libres: libres,
        pendientes: estado.pendientes - 1,
        ocupados: Map.put(estado.ocupados, pid, clave)
    }
  end

  defp vecinos(carrera) do
    case Links.descargar(carrera.url_objetivo) do
      {:ok, html} ->
        html
        |> parsear(carrera.url_objetivo, carrera)
        |> Enum.reduce(%{}, fn {clave, _}, vecinos -> Map.put(vecinos, clave, true) end)

      _ ->
        %{}
    end
  end

  defp trabajar(coordinador, carrera) do
    send(coordinador, {:pedir, self()})

    receive do
      {:pagina, clave} ->
        send(coordinador, visitar_aparte(clave, carrera))
        trabajar(coordinador, carrera)

      :parar ->
        :ok
    end
  end

  defp visitar_aparte(clave, carrera) do
    yo = self()
    pid = spawn_link(fn -> send(yo, {self(), visitar(clave, carrera)}) end)

    receive do
      {^pid, resultado} -> resultado
    end
  end

  defp visitar(clave, carrera) do
    case :ets.lookup(@padres, clave) do
      [{^clave, {_padre, url}}] ->
        case Links.descargar(url) do
          {:ok, html} ->
            links = parsear(html, url, carrera)

            case Enum.find(links, fn {c, _} -> c == carrera.objetivo end) do
              nil ->
                links = Enum.reject(links, fn {c, _} -> :ets.member(@vistos, c) end)
                {:links, clave, links}

              _ ->
                {:encontrado, clave}
            end

          :no_existe ->
            :no_existe

          :error ->
            {:fallo, clave}
        end

      [] ->
        :no_existe
    end
  end

  defp parsear(html, url, carrera) do
    send(carrera.coordinador, {:turno, self()})

    receive do
      :turno -> :ok
    end

    links = Links.extraer(html, url, carrera.prefijo)
    send(carrera.coordinador, {:soltar, self()})
    links
  end

  defp reconstruir(clave), do: recorrer(clave, [])

  defp recorrer(clave, urls) do
    case :ets.lookup(@padres, clave) do
      [{^clave, {nil, url}}] -> [url | urls]
      [{^clave, {padre, url}}] -> recorrer(padre, [url | urls])
      [] -> urls
    end
  end

  defp profundidad(clave), do: prof(clave, 0)

  defp prof(_clave, n) when n >= @profundidad, do: n

  defp prof(clave, n) do
    case :ets.lookup(@padres, clave) do
      [{^clave, {nil, _url}}] -> n
      [{^clave, {padre, _url}}] -> prof(padre, n + 1)
      [] -> n
    end
  end
end

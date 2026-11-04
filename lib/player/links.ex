defmodule Player.Links do
  def descargar(url, intentos \\ 3) do
    case pedir(url) do
      {:ok, html} ->
        {:ok, html}

      :no_existe ->
        :no_existe

      :error ->
        if intentos > 1 do
          esperar()
          descargar(url, intentos - 1)
        else
          :error
        end
    end
  end

  def extraer(html, url, prefijo) do
    base = URI.parse(url)

    ~r/<a\s(?:[^>]*?\s)?href="([^"]*)"/
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(&resolver(String.replace(&1, "&amp;", "&"), base, prefijo))
  end

  def clave(url) do
    uri = URI.parse(url)
    ruta = uri.path |> to_string() |> URI.decode() |> String.trim_trailing("/")
    "#{uri.scheme}://#{uri.host}#{puerto(uri)}#{ruta}"
  end

  def prefijo(url) do
    base = url |> clave() |> String.split("/") |> Enum.take(5) |> Enum.join("/")
    base <> "/"
  end

  defp esperar do
    receive do
    after
      200 -> :ok
    end
  end

  defp pedir(url) do
    try do
      case Req.get(url, receive_timeout: 3_000, connect_options: [timeout: 3_000], retry: false) do
        {:ok, %Req.Response{status: 200, body: html}} when is_binary(html) -> {:ok, html}
        {:ok, %Req.Response{status: 404}} -> :no_existe
        _ -> :error
      end
    rescue
      _ -> :error
    end
  end

  defp resolver("#" <> _, _base, _prefijo), do: []

  defp resolver(href, base, prefijo) do
    try do
      link = base |> URI.merge(href) |> Map.put(:fragment, nil) |> URI.to_string()
      clave = clave(link)

      if String.starts_with?(clave, prefijo) and not String.starts_with?(clave, prefijo <> "-/") do
        [{clave, link}]
      else
        []
      end
    rescue
      _ -> []
    end
  end

  defp puerto(%URI{scheme: "http", port: 80}), do: ""
  defp puerto(%URI{scheme: "https", port: 443}), do: ""
  defp puerto(%URI{port: nil}), do: ""
  defp puerto(%URI{port: n}), do: ":#{n}"
end

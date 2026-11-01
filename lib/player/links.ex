defmodule Player.Links do
  def descargar(url, intentos \\ 3) do
    case pedir(url) do
      {:ok, html} ->
        {:ok, html}

      :error ->
        if intentos > 1 do
          descargar(url, intentos - 1)
        else
          :error
        end
    end
  end

  def extraer(html, url, prefijo) do
    ~r/<a\s(?:[^>]*?\s)?href="([^"]*)"/
    |> Regex.scan(html, capture: :all_but_first)
    |> List.flatten()
    |> Enum.uniq()
    |> Enum.flat_map(&resolver(String.replace(&1, "&amp;", "&"), url, prefijo))
  end

  def clave(url) do
    uri = URI.parse(url)
    ruta = uri.path |> to_string() |> URI.decode() |> String.trim_trailing("/")
    "#{uri.scheme}://#{uri.host}#{puerto(uri)}#{ruta}"
  end

  def prefijo(url) do
    url |> clave() |> String.split("/") |> Enum.take(5)
  end

  defp pedir(url) do
    try do
      case Req.get(url, receive_timeout: 3_000, connect_options: [timeout: 3_000], retry: false) do
        {:ok, %Req.Response{status: 200, body: html}} when is_binary(html) -> {:ok, html}
        _ -> :error
      end
    rescue
      _ -> :error
    end
  end

  defp resolver("#" <> _, _url, _prefijo), do: []

  defp resolver(href, url, prefijo) do
    try do
      link = url |> URI.merge(href) |> Map.put(:fragment, nil) |> URI.to_string()
      clave = clave(link)

      case String.split(clave, "/") do
        [_, _, _, _, _, "-" | _] ->
          []

        [_, _, _, _, _, _ | _] = partes ->
          if Enum.take(partes, 5) == prefijo do
            [{clave, link}]
          else
            []
          end

        _ ->
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

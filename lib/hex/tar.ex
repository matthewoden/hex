defmodule Hex.Tar do
  def create(meta, files, cleanup_tarball? \\ true) do
    # FIXME: remove this, update tests instead
    meta = Map.put_new(meta, :files, [])

    files =
      Enum.map(files, fn
        {path, contents} -> {Hex.string_to_charlist(path), contents}
        path -> Hex.string_to_charlist(path)
      end)
    {:ok, {tar, checksum}} = :hex_tar.create(meta, files, keep_tarball: !cleanup_tarball?)
    {tar, List.to_string(checksum)}
  end

  def unpack(path, dest, _repo, _name, _version) do
    # FIXME: check checksum, name, version
    path = Hex.string_to_charlist(path)
    dest = Hex.string_to_charlist(dest)
    {:ok, {_checksum, meta}} = :hex_tar.unpack(path, destination: dest)
    meta
  end

  def extract_contents(file, dest, opts \\ []) do
    mode = opts[:mode] || :binary
    case :hex_erl_tar.extract({mode, file}, [:compressed, cwd: dest]) do
      :ok ->
        Path.join(dest, "**")
        |> Path.wildcard()
        |> Enum.each(&File.touch!/1)
        :ok
      {:error, reason} ->
        Mix.raise "Unpacking inner tarball failed: " <> format_error(reason)
    end
  end

  defp format_error({_path, reason}) do
    format_error(reason)
  end
  defp format_error(reason) do
    :hex_erl_tar.format_error(reason)
    |> List.to_string()
  end
end

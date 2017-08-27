defmodule Hex.Tar do
  @supported ["3"]
  @required_files ~w(VERSION CHECKSUM metadata.config contents.tar.gz)c

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

  def unpack(path, dest, repo, name, version) do
    case :hex_erl_tar.extract(path, [:memory]) do
      {:ok, files} ->
        files = Enum.into(files, %{})
        check_version(files['VERSION'])
        check_files(files)
        checksum(files, repo, name, version)
        extract_contents(files['contents.tar.gz'], dest)
        copy_metadata(files['metadata.config'], dest)
        decode_metadata(files['metadata.config'])

      :ok ->
        Mix.raise "Unpacking tarball failed: tarball empty"

      {:error, reason} ->
        Mix.raise "Unpacking tarball failed: " <> format_error(reason)
    end
  end

  defp check_files(files) do
    files = Map.keys(files)
    diff_files(@required_files, files)
  end

  defp diff_files(required, given) do
    diff = required -- given
    if diff != [] do
      diff = Enum.join(diff, ", ")
      Mix.raise "Missing files in tarball #{diff}"
    end
  end

  defp check_version(version) do
    unless version in @supported do
      Mix.raise "Unsupported tarball version #{version}. " <>
                 "Try updating Hex with `mix local.hex`."
    end
  end

  defp checksum(files, repo, name, version) do
    case Base.decode16(files['CHECKSUM'], case: :mixed) do
      {:ok, tar_checksum} ->
        meta = files['metadata.config']
        blob = files['VERSION'] <> meta <> files['contents.tar.gz']
        registry_checksum = Hex.Registry.Server.checksum(repo, to_string(name), version)
        checksum = :crypto.hash(:sha256, blob)

        if checksum != tar_checksum do
          Mix.raise "Checksum mismatch in tarball"
        end
        if checksum != registry_checksum do
          Mix.raise "Checksum mismatch against registry"
        end

      :error ->
        Mix.raise "Checksum invalid"
    end
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

  defp decode_metadata(contents) do
    string = safe_to_charlist(contents)
    case :safe_erl_term.string(string) do
      {:ok, tokens, _line} ->
        try do
          terms = :safe_erl_term.terms(tokens)
          Enum.into(terms, %{})
        rescue
          FunctionClauseError ->
            Mix.raise "Error reading package metadata: invalid terms"
          ArgumentError ->
            Mix.raise "Error reading package metadata: not in key-value format"
        end

      {:error, reason} ->
        Mix.raise "Error reading package metadata: #{inspect reason}"
    end
  end

  defp copy_metadata(content, dest) do
    file_name = "hex_metadata.config"
    path = Path.join(dest, file_name)

    if File.exists?(path) do
      Hex.Shell.warn("#{file_name} already exists")
    else
      File.write!(path, content)
    end
  end

  # Some older packages have invalid unicode
  defp safe_to_charlist(string) do
    try do
      Hex.string_to_charlist(string)
    rescue
      UnicodeConversionError ->
        :erlang.binary_to_list(string)
    end
  end
end

defmodule Hex.State do
  @name __MODULE__
  @logged_keys ~w(http_proxy HTTP_PROXY https_proxy HTTPS_PROXY)
  @default_home "~/.hex"
  @default_url "https://hex.pm/api"
  @default_mirror "https://s3.amazonaws.com/s3.hex.pm"

  @hexpm_pk """
  -----BEGIN PUBLIC KEY-----
  MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEApqREcFDt5vV21JVe2QNB
  Edvzk6w36aNFhVGWN5toNJRjRJ6m4hIuG4KaXtDWVLjnvct6MYMfqhC79HAGwyF+
  IqR6Q6a5bbFSsImgBJwz1oadoVKD6ZNetAuCIK84cjMrEFRkELtEIPNHblCzUkkM
  3rS9+DPlnfG8hBvGi6tvQIuZmXGCxF/73hU0/MyGhbmEjIKRtG6b0sJYKelRLTPW
  XgK7s5pESgiwf2YC/2MGDXjAJfpfCd0RpLdvd4eRiXtVlE9qO9bND94E7PgQ/xqZ
  J1i2xWFndWa6nfFnRxZmCStCOZWYYPlaxr+FZceFbpMwzTNs4g3d4tLNUcbKAIH4
  0wIDAQAB
  -----END PUBLIC KEY-----
  """

  def start_link do
    config = Hex.Config.read
    Agent.start_link(__MODULE__, :init, [config], [name: @name])
  end

  def stop do
    Agent.stop(@name)
  end

  def init(config) do
    cdn    = load_config(config, ["HEX_CDN"], :cdn_url)
    mirror = load_config(config, ["HEX_MIRROR"], :mirror_url)

    if cdn do
      Hex.Shell.warn "HEX_CDN environment variable and cdn_url config has been " <>
                     "deprecated in favor of HEX_MIRROR/HEX_REPO and mirror_url/cdn_url " <>
                     "respectively. Set HEX_MIRROR when using a hex.pm and set HEX_REPO " <>
                     "when using a repository different than hex.pm." 
    end

    %{home:             System.get_env("HEX_HOME") |> default(@default_home) |> Path.expand,
      api:              load_config(config, ["HEX_API"], :api_url) |> default(@default_url),
      repo:             load_config(config, ["HEX_REPO"], :repo_url),
      mirror:           default(mirror || cdn, @default_mirror),
      http_proxy:       load_config(config, ["http_proxy", "HTTP_PROXY"], :http_proxy),
      https_proxy:      load_config(config, ["https_proxy", "HTTPS_PROXY"], :https_proxy),
      offline?:         load_config(config, ["HEX_OFFLINE"], :offline) |> to_boolean |> default(false),
      check_cert?:      load_config(config, ["HEX_UNSAFE_HTTPS"], :unsafe_https) |> to_boolean |> default(true),
      check_registry?:  load_config(config, ["HEX_UNSAFE_REGISTRY"], :unsafe_registry) |> to_boolean |> default(true),
      hexpm_pk:         @hexpm_pk,
      registry_updated: false}
  end

  def fetch(key) do
    Agent.get(@name, Map, :fetch, [key])
  end

  def fetch!(key) do
    Agent.get(@name, Map, :fetch!, [key])
  end

  def get(key, default \\ nil) do
    Agent.get(@name, Map, :get, [key, default])
  end

  def put(key, value) do
    Agent.update(@name, Map, :put, [key, value])
  end

  def get_all do
    Agent.get(@name, & &1)
  end

  def put_all(map) do
    Agent.update(@name, fn _ -> map end)
  end

  defp load_config(config, envs, config_key) do
    result =
      envs
      |> Enum.map(&env_exists/1)
      |> Enum.find(&(not is_nil &1))
      || config_exists(config, config_key)

    if result do
      {key, value} = result

      log_value(key, value)
      value
    end
  end

  defp env_exists(key) do
    if value = System.get_env(key) do
      {key, value}
    else
      nil
    end
  end

  defp config_exists(config, key) do
    if value = Keyword.get(config, key) do
      {"config[:#{key}]", value}
    else
      nil
    end
  end

  defp log_value(key, value) do
    if Enum.member?(@logged_keys, key) do
      Hex.Shell.info "Using #{key} = #{value}"
    end
  end

  defp to_boolean(nil),     do: nil
  defp to_boolean(false),   do: false
  defp to_boolean(true),    do: true
  defp to_boolean("0"),     do: false
  defp to_boolean("1"),     do: true
  defp to_boolean("false"), do: false
  defp to_boolean("true"),  do: true

  defp default(nil, value), do: value
  defp default(value, _),   do: value
end

defmodule Ejabberd.Mixfile do
  use Mix.Project

  def project do
    [app: :ejabberd,
     version: "19.8.0",
     description: description(),
     elixir: "~> 1.4",
     elixirc_paths: ["lib"],
     compile_path: ".",
     compilers: [:asn1] ++ Mix.compilers,
     erlc_options: erlc_options(),
     erlc_paths: ["asn1", "src"],
     # Elixir tests are starting the part of ejabberd they need
     aliases: [test: "test --no-start"],
     package: package(),
     deps: deps()]
  end

  def description do
    """
    Robust, ubiquitous and massively scalable Jabber / XMPP Instant Messaging platform.
    """
  end

  def application do
    [mod: {:ejabberd_app, []},
     applications: [:kernel, :stdlib, :sasl, :ssl],
     included_applications: [:lager, :mnesia, :inets, :p1_utils, :cache_tab,
                             :fast_tls, :stringprep, :fast_xml, :xmpp, :mqtree,
                             :stun, :fast_yaml, :esip, :jiffy, :p1_oauth2,
                             :eimp, :base64url, :jose, :pkix, :os_mon, :yconf]
     ++ cond_apps()]
  end

  defp if_function_exported(mod, fun, arity, okResult) do
    :code.ensure_loaded(mod)
    if :erlang.function_exported(mod, fun, arity) do
      okResult
    else
      []
    end
  end

  defp if_version_above(ver, okResult) do
    if :erlang.system_info(:otp_release) > ver do
      okResult
    else
      []
    end
  end

  defp erlc_options do
    # Use our own includes + includes from all dependencies
    includes = ["include"] ++ deps_include(["fast_xml", "xmpp", "p1_utils"])
    [:debug_info, {:d, :ELIXIR_ENABLED}] ++ cond_options() ++ Enum.map(includes, fn(path) -> {:i, path} end) ++
    if_version_above('20', [{:d, :DEPRECATED_GET_STACKTRACE}]) ++
    if_function_exported(:erl_error, :format_exception, 6, [{:d, :HAVE_ERL_ERROR}])
  end

  defp cond_options do
    for {:true, option} <- [{config(:sip), {:d, :SIP}},
                            {config(:stun), {:d, :STUN}},
                            {config(:roster_gateway_workaround), {:d, :ROSTER_GATWAY_WORKAROUND}},
                            {config(:new_sql_schema), {:d, :NEW_SQL_SCHEMA}}
                           ], do:
    option
  end

  defp deps do
    [{:lager, "~> 3.6.0"},
     {:p1_utils, "~> 1.0"},
     {:fast_xml, "~> 1.1"},
     {:xmpp, "~> 1.4.0"},
     {:cache_tab, "~> 1.0"},
     {:stringprep, "~> 1.0"},
     {:fast_yaml, "~> 1.0"},
     {:fast_tls, "~> 1.1"},
     {:stun, "~> 1.0"},
     {:esip, "~> 1.0"},
     {:p1_mysql, "~> 1.0"},
     {:mqtree, "~> 1.0"},
     {:p1_pgsql, "~> 1.1"},
     {:jiffy, "~> 0.14.7"},
     {:p1_oauth2, "~> 0.6.1"},
     {:distillery, "~> 2.0"},
     {:pkix, "~> 1.0"},
     {:ex_doc, ">= 0.0.0", only: :dev},
     {:eimp, "~> 1.0"},
     {:base64url, "~> 0.0.1"},
     {:yconf, "~> 1.0"},
     {:jose, "~> 1.8"}]
    ++ cond_deps()
  end

  defp deps_include(deps) do
    base = if Mix.Project.umbrella?() do
      "../../deps"
    else
      case Mix.Project.deps_paths()[:ejabberd] do
        nil -> "deps"
        _ -> ".."
      end
    end
    Enum.map(deps, fn dep -> base<>"/#{dep}/include" end)
  end

  defp cond_deps do
    for {:true, dep} <- [{config(:sqlite), {:sqlite3, "~> 1.1"}},
                         {config(:redis), {:eredis, "~> 1.0"}},
                         {config(:zlib), {:ezlib, "~> 1.0"}},
                         {config(:pam), {:epam, "~> 1.0"}},
                         {config(:tools), {:luerl, "~> 0.3.1"}}], do:
      dep
  end

  defp cond_apps do
    for {:true, app} <- [{config(:redis), :eredis},
                         {config(:mysql), :p1_mysql},
                         {config(:pgsql), :p1_pgsql},
                         {config(:sqlite), :sqlite3},
                         {config(:zlib), :ezlib}], do:
      app
  end

  defp package do
    [# These are the default files included in the package
      files: ["lib", "src", "priv", "mix.exs", "include", "README.md", "COPYING"],
      maintainers: ["ProcessOne"],
      licenses: ["GPLv2"],
      links: %{"Site" => "https://www.ejabberd.im",
               "Documentation" => "http://docs.ejabberd.im",
               "Source" => "https://github.com/processone/ejabberd",
               "ProcessOne" => "http://www.process-one.net/"}]
  end

  defp vars do
    case :file.consult("vars.config") do
      {:ok,config} -> config
      _ -> [zlib: true]
    end
  end

  defp config(key) do
    case vars()[key] do
      nil -> false
      value -> value
    end
  end

end

defmodule Mix.Tasks.Compile.Asn1 do
  use Mix.Task
  alias Mix.Compilers.Erlang

  @recursive true
  @manifest ".compile.asn1"

  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: [force: :boolean])

    project      = Mix.Project.config
    source_paths = project[:asn1_paths] || ["asn1"]
    dest_paths    = project[:asn1_target] || ["src"]
    mappings     = Enum.zip(source_paths, dest_paths)
    options      = project[:asn1_options] || []

    force = case opts[:force] do
        :true -> [force: true]
        _ -> [force: false]
    end

    Erlang.compile(manifest(), mappings, :asn1, :erl, force, fn
      input, output ->
        options = options ++ [:noobj, outdir: Erlang.to_erl_file(Path.dirname(output))]
        case :asn1ct.compile(Erlang.to_erl_file(input), options) do
          :ok -> {:ok, :done}
          error -> error
        end
    end)
  end

  def manifests, do: [manifest()]
  defp manifest, do: Path.join(Mix.Project.manifest_path, @manifest)

  def clean, do: Erlang.clean(manifest())
end

defmodule FarmbotExt.AMQP.AutoSyncChannel do
  @moduledoc """
  This module provides an AMQP channel for
  auto-sync messages from the FarmBot API.
  SEE:
    https://developer.farm.bot/docs/realtime-updates-auto-sync#section-example-auto-sync-subscriptions
  """
  use GenServer
  use AMQP

  alias FarmbotCore.{BotState, JSON, Leds}
  alias FarmbotExt.AMQP.{ConnectionWorker, AutoSyncAssetHandler}
  alias FarmbotExt.API.{EagerLoader, Preloader}
  alias FarmbotExt.AMQP.Support

  require FarmbotCore.Logger
  require FarmbotTelemetry
  require Support

  # The API dispatches messages for other resources, but these
  # are the only ones that Farmbot needs to sync.
  @known_kinds ~w(
    Device
    FarmEvent
    FarmwareEnv
    FarmwareInstallation
    FbosConfig
    FirmwareConfig
    Peripheral
    PinBinding
    Point
    PointGroup
    Regimen
    Sensor
    Sequence
    Tool
  )

  defstruct [:conn, :chan, :jwt, :preloaded]

  alias __MODULE__, as: State

  @doc "Gets status of auto_sync connection for diagnostics / tests."
  def network_status(server \\ __MODULE__) do
    GenServer.call(server, :network_status)
  end

  @doc false
  def start_link(args, opts \\ [name: __MODULE__]) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  def init(args) do
    jwt = Keyword.fetch!(args, :jwt)

    send(self(), :preload)

    {:ok, %State{conn: nil, chan: nil, jwt: jwt, preloaded: false}}
  end

  def terminate(reason, state) do
    Support.handle_termination(reason, state, "Auto Sync")

    try do
      EagerLoader.Supervisor.drop_all_cache()
    catch
      _, _ ->
        :ok
    end
  end

  def handle_info(:preload, state) do
    _ = Leds.green(:really_fast_blink)

    with :ok <- Preloader.preload_all() do
      _ = Leds.green(:solid)
      BotState.set_sync_status("synced")

      send(self(), :connect)

      {:noreply, %{state | preloaded: true}}
    else
      {:error, reason} ->
        BotState.set_sync_status("sync_error")
        _ = Leds.green(:slow_blink)
        FarmbotCore.Logger.error(1, "Error preloading. #{inspect(reason)}")
        FarmbotTelemetry.event(:asset_sync, :preload_error, nil, error: inspect(reason))
        FarmbotExt.Time.send_after(self(), :preload, 5000)

        {:noreply, state}
    end
  end

  def handle_info(:connect, state) do
    result = ConnectionWorker.maybe_connect_autosync(state.jwt.bot)
    compute_reply_from_amqp_state(state, result)
  end

  # Confirmation sent by the broker after registering this process as a consumer
  def handle_info({:basic_consume_ok, _}, state) do
    {:noreply, state}
  end

  # Sent by the broker when the consumer is
  # unexpectedly cancelled (such as after a queue deletion)
  def handle_info({:basic_cancel, _}, state) do
    {:stop, :normal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  def handle_info({:basic_cancel_ok, _}, state) do
    {:noreply, state}
  end

  def handle_info({:basic_deliver, payload, %{routing_key: key}}, %{preloaded: true} = state) do
    # Logger.warn "AUTOSYNC PAYLOAD: #{inspect(key)} #{inspect(payload)}"
    chan = state.chan
    data = JSON.decode!(payload)
    device = state.jwt.bot
    label = data["args"]["label"]
    body = data["body"]

    case String.split(key, ".") do
      ["bot", ^device, "sync", asset_kind, id_str] when asset_kind in @known_kinds ->
        id = data["id"] || String.to_integer(id_str)
        _ = AutoSyncAssetHandler.handle_asset(asset_kind, id, body)

      _ ->
        ""
        # Logger.info("ignoring route: #{key}")
    end

    :ok = ConnectionWorker.rpc_reply(chan, device, label)
    {:noreply, state}
  end

  def handle_info({:basic_deliver, _, _}, %{preloaded: false} = state) do
    send(self(), :preload)
    {:noreply, state}
  end

  Support.catch_unhandled_messages()

  def handle_call(:network_status, _, state) do
    reply = %{conn: state.conn, chan: state.chan, preloaded: state.preloaded}

    {:reply, reply, state}
  end

  defp compute_reply_from_amqp_state(state, %{conn: conn, chan: chan}) do
    {:noreply, %{state | conn: conn, chan: chan}}
  end

  defp compute_reply_from_amqp_state(state, error) do
    # Run error warning if error not nil
    if error,
      do: FarmbotCore.Logger.error(1, "Failed to connect to AutoSync channel: #{inspect(error)}")

    {:noreply, %{state | conn: nil, chan: nil}}
  end
end

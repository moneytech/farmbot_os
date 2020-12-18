defmodule FarmbotOS.Platform.Target.InfoWorker.WifiLevel do
  @moduledoc """
  Worker process responsible for reporting current wifi
  power levels to the bot_state server
  """

  @report_interval 7_000

  use GenServer
  require FarmbotCore.Logger
  alias FarmbotCore.BotState

  @doc false
  def start_link(args) do
    GenServer.start_link(__MODULE__, args)
  end

  @impl GenServer
  def init(_args) do
    send(self(), :load_network_config)
    {:ok, %{ssid: nil}}
  end

  def handle_signal_info({:ok, signal_info}) do
    :ok = BotState.report_wifi_level(signal_info.signal_dbm)
    :ok = BotState.report_wifi_level_percent(signal_info.signal_percent)
  end

  def handle_signal_info(error), do: error

  @impl GenServer
  def handle_info(:timeout, state) do
    handle_signal_info(VintageNet.ioctl("wlan0", :signal_poll))
    {:noreply, state, @report_interval}
  end

  def handle_info(:load_network_config, state) do
    if FarmbotCore.Config.get_network_config("eth0") do
      FarmbotCore.Logger.warn(3, """
      FarmBot configured to use ethernet
      Disabling WiFi status reporting
      """)

      VintageNet.subscribe(["interface", "eth0"])

      {:noreply, state}
    else
      case FarmbotCore.Config.get_network_config("wlan0") do
        %{ssid: ssid} ->
          VintageNet.subscribe(["interface", "wlan0"])
          {:noreply, %{state | ssid: ssid}, @report_interval}

        nil ->
          Process.send_after(self(), :load_network_config, 10_000)
          {:noreply, %{state | ssid: nil}}
      end
    end
  end

  def handle_info(
        {VintageNet, ["interface", _, "addresses"], _old,
         [%{address: address} | _], _meta},
        state
      ) do
    FarmbotCore.BotState.set_private_ip(to_string(:inet.ntoa(address)))
    {:noreply, state, @report_interval}
  end

  def handle_info({VintageNet, _property, _old, _new, _meta}, state) do
    {:noreply, state, @report_interval}
  end
end

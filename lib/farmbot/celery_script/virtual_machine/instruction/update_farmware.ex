defmodule Farmbot.CeleryScript.VirtualMachine.Instruction.UpdateFarmware do
  @moduledoc """
  update_farmware
  """

  alias Farmbot.CeleryScript.AST
  alias Farmbot.CeleryScript.VirtualMachine.Instruction
  @behaviour Instruction

  def precompile(%AST{} = ast) do
    {:ok, ast}
  end

  def execute(args, body) do

  end
end

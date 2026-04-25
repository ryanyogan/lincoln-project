defmodule Lincoln.Autonomy.EvolutionApplyTest do
  @moduledoc """
  Verifies the safety gates in `Lincoln.Autonomy.Evolution.apply_change/1`.

  The two gates exist because Lincoln's self-improvement system has, in
  practice, written truncated source files that broke the running server.
  These tests pin the contract that bad content cannot land on disk.
  """

  use ExUnit.Case, async: true

  alias Lincoln.Autonomy.Evolution

  setup do
    # Evolution.apply_change/1 joins file_path against @project_root, so the
    # test must use a path *inside* project_root. We use a tempdir under
    # project_root/_evolution_test/ which is namespaced enough to be safe.
    project_root = Lincoln.SelfAwareness.project_root()
    test_dir_rel = "_evolution_test_#{:erlang.unique_integer([:positive])}"
    test_dir_abs = Path.join(project_root, test_dir_rel)
    File.mkdir_p!(test_dir_abs)

    file_name = "test_#{:erlang.unique_integer([:positive])}.ex"
    rel_path = Path.join(test_dir_rel, file_name)
    abs_path = Path.join(test_dir_abs, file_name)

    on_exit(fn -> File.rm_rf!(test_dir_abs) end)

    %{rel_path: rel_path, abs_path: abs_path, test_dir_abs: test_dir_abs}
  end

  describe "syntax gate" do
    test "refuses to apply truncated Elixir content", %{rel_path: rel_path, abs_path: abs_path} do
      File.write!(abs_path, "defmodule Original do\n  def hi, do: :ok\nend\n")

      change = %{
        file_path: rel_path,
        new_content: "defmodule Broken do\n  def x, do: {:ok, _\n"
      }

      assert {:error, {:syntax_error, _}} = Evolution.apply_change(change)
      # File on disk is unchanged
      assert File.read!(abs_path) =~ "Original"
    end

    test "applies syntactically-valid Elixir content", %{rel_path: rel_path, abs_path: abs_path} do
      File.write!(abs_path, "defmodule Original do\n  def hi, do: :ok\nend\n")

      change = %{
        file_path: rel_path,
        new_content: "defmodule Replacement do\n  def hi, do: :hello\nend\n"
      }

      assert {:ok, _} = Evolution.apply_change(change)
      assert File.read!(abs_path) =~ "Replacement"
    end

    test "skips syntax check for non-.ex/.exs files", %{test_dir_abs: test_dir_abs} do
      project_root = Lincoln.SelfAwareness.project_root()
      txt_name = "test_#{:erlang.unique_integer([:positive])}.txt"
      rel_path = Path.relative_to(Path.join(test_dir_abs, txt_name), project_root)

      change = %{
        file_path: rel_path,
        new_content: "this is not valid elixir but it is fine for txt"
      }

      assert {:ok, _} = Evolution.apply_change(change)
    end
  end

  describe "atomic write" do
    test "no .tmp leftover files after a successful apply", %{
      rel_path: rel_path,
      abs_path: abs_path,
      test_dir_abs: test_dir_abs
    } do
      change = %{
        file_path: rel_path,
        new_content: "defmodule Atomic do\n  def x, do: 1\nend\n"
      }

      assert {:ok, _} = Evolution.apply_change(change)

      leftovers =
        test_dir_abs
        |> File.ls!()
        |> Enum.filter(&String.contains?(&1, ".tmp."))
        |> Enum.filter(&String.starts_with?(&1, Path.basename(abs_path)))

      assert leftovers == []
    end
  end
end

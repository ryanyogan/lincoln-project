defmodule LincolnWeb.API.ErrorJSON do
  @moduledoc """
  JSON error responses for the API.
  """

  def render("error.json", %{changeset: changeset}) do
    %{
      error: %{
        message: "Validation failed",
        details: Ecto.Changeset.traverse_errors(changeset, &translate_error/1)
      }
    }
  end

  def render("error.json", %{message: message}) do
    %{
      error: %{
        message: message
      }
    }
  end

  defp translate_error({msg, opts}) do
    Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end
end

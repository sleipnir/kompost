defmodule Mix.Tasks.Bonny.Gen.Manifest.KompostCustomizer do
  @moduledoc """
  Implements a callback to override manifests generated by `mix bonny.gen.manifest`
  """

  @doc """
  This function is called for every resource generated by `mix bonny.gen.manifest`.
  Use pattern matching to override specific resources.

  Be careful in your pattern matching. Sometimes the map keys are strings,
  sometimes they are atoms.

  ### Examples

  def override(%{kind: "ServiceAccount"} = resource) do
    put_in(resource, ~w(metadata labels foo)a, "bar")
  end
  """

  @spec override(Bonny.Resource.t()) :: Bonny.Resource.t()

  def override(%{kind: "CustomResourceDefinition"} = resource) do
    resource
    |> Map.update!(:metadata, fn
      %{:labels => labels} = metadata when labels == %{} -> Map.delete(metadata, :labels)
      metadata -> metadata
    end)
    |> update_in([:spec, :versions, Access.all()], fn
      version ->
        version
        |> Map.from_struct()
        |> Enum.reject(fn
          {:additionalPrinterColumns, []} -> true
          {:deprecated, false} -> true
          _ -> false
        end)
        |> Map.new()
    end)
  end

  # fallback
  def override(resource), do: resource
end

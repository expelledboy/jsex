defmodule Nodelet.MixProject do
  use Mix.Project

  @description "Duplex remote calls between Elixir and Node.JS over Port"

  def project do
    [
      app: :nodelet,
      version: "0.1.0",
      elixir: "~> 1.7",
      description: @description,
      package: package(),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:jason, "~> 1.1"},
      {:mock, "~> 0.3", only: :test}
    ]
  end

  defp package do
    [
      licenses: ["Apache 2.0"],
      maintainers: ["expelledboy"],
      links: %{"GitHub" => "https://github.com/expelledboy/nodelet"}
    ]
  end
end

defmodule WAservix.MixProject do
  use Mix.Project

  @version "1.0.1"
  @source_url "https://github.com/TekservixHQ/waservix-elixir"

  def project do
    [
      app: :waservix,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "WAservix",
      description:
        "WAservix WhatsApp API Gateway: official Elixir client by Tekservix. Send WhatsApp messages, images and documents from your own number, with status tracking and webhooks.",
      source_url: @source_url,
      homepage_url: "https://tekservix.com/waservix/",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [extra_applications: [:logger]]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:plug, "~> 1.14", only: :test},
      {:ex_doc, ">= 0.0.0", only: :dev, runtime: false}
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Website" => "https://tekservix.com/waservix/",
        "API reference" => "https://tekservix.com/waservix/docs/"
      },
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md .formatter.exs)
    ]
  end

  defp docs do
    [main: "readme", extras: ["README.md", "CHANGELOG.md"], source_ref: "v#{@version}"]
  end
end

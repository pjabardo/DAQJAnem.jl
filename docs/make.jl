using DAQJAnem
using Documenter

DocMeta.setdocmeta!(DAQJAnem, :DocTestSetup, :(using DAQJAnem); recursive=true)

makedocs(;
    modules=[DAQJAnem],
    authors="Paulo José Saiz Jabardo",
    repo="https://github.com/pjsjipt/DAQJAnem.jl/blob/{commit}{path}#{line}",
    sitename="DAQJAnem.jl",
    format=Documenter.HTML(;
        prettyurls=get(ENV, "CI", "false") == "true",
        edit_link="main",
        assets=String[],
    ),
    pages=[
        "Home" => "index.md",
    ],
)

# Changelog

# v0.5.0

Breaking changes:

* Minimum Elixir version is now 1.16
* `Bow.Exec` and `erlexec` dependency removed. Generate versions in `transform/3` with
  `Bow.with_output/2` and any tool you like (`System.cmd/3`, Vix, MuonTrap, erlexec...).
  `:exec_timeout` config removed
* `tesla` dependency removed. Remote files are downloaded with `:httpc` by default (`Bow.Downloader.Httpc`),
  use `config :bow, downloader: MyDownloader` to plug in your own `Bow.Downloader` (e.g. Req or Tesla)
* `Bow.Download.download(client, url)` is now `Bow.Download.download(url, opts)`
* `Bow.Ecto.cast_uploads/4` and `Bow.Ecto.download_params/3` take options (e.g. `downloader: ...`)
  instead of a Tesla client
* `Bow.Download.download/2` errors are `{:error, %{status: status, headers: headers}}`
  and `{:error, :too_many_redirects}`

Other changes:

* Updated dependencies (Ecto 3.10+, Plug 1.14+, ExAws 2.4+)
* Add `Bow.with_output/2` helper for writing processed files
* Downloaded files are streamed to disk instead of being loaded into memory
* fix: `Bow.Download` no longer requires Ecto

# v0.4.3

* fix: handle valid URL without file path

# v0.4.2

* Fix `assets_host()` callback return type

## v0.4.1

* Add `assets_host/0` to `Bow.Uploader` for custom assets host

## v0.4.0

* Relaxed and updated dependencies
* Minimum Elixir version is now 1.4

## v0.3.3

* Fix file extension detection

## v0.3.2

* Typespecs improvements

## v0.3.1

* Typespecs improvements

## v0.3.0

* Upgraded tesla dependency
* Added missing callbacks required by Ecto 3.2 to generated `Ecto.Type` modules

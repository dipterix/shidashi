# shidashi 0.1.6

* Load scripts starting with `shared-` when loading modules

# shidashi 0.1.5

* Fixed `accordion` and `card_tabset` not working properly when `inputId` starts with digits
* Updated templates and used `npm` to compile
* Session information now stores at `userData` instead of risky `cache`
* Ensured at least template root directory is available

# shidashi 0.1.4

* Fixed a bug that makes application fail to launch on `Windows`
* Added support to evaluated expressions before launching the application, allowing actions such as setting global options and loading data


# shidashi 0.1.3

* Allow modules to be hidden from the sidebar

# shidashi 0.1.2

* Fixed group name not handled correctly as factors
* Module `URL` respects domain now and is generated with relative path
* Works on `rstudio-server` now
* More stable behavior to `flex_container`
* Allow output (mainly plot and text outputs) to be reset
* Fixed `iframe` height not set correctly
* Enhanced 500 page to print out `traceback`, helping debug the errors
* Added `flex_break` to allow wrapping elements in flex container
* Added `remove_class` to remove `HTML` class from a string
* Allow to set `data-title` to cards

# shidashi 0.1.0

* Added a `NEWS.md` file to track changes to the package.

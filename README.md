# A web map from the Dulux colours of New Zealand
This is just a demonstration of the flexibility of the R ecosystem for quickly putting together a [web map](https://dosull.github.io/dulux-colours-map/maps/).

The map is a somewhat silly (but irrestible to a geographer) take on the [Dulux 'colours of New Zealand' range of paints](https://www.dulux.co.nz/colour/colours-of-new-zealand).

Some alternative maps where I've interpolated RGB values at point locations to make a smoothed raster colour map are also available:

+ [Triangulation](https://dosull.github.io/dulux-colours-map/maps/triangulation.html) based using `akima::interp` with `linear = TRUE` (this one is at ~500m resolution, where the others are more like 2500m)
+ [Inverse-distance weighting](https://dosull.github.io/dulux-colours-map/maps/idw.html) using `spatstat::idw` with `power = 4`
+ [Thin plate splines](https://dosull.github.io/dulux-colours-map/maps/splines.html) using `fields::Tps` with `m = 3`
+ [Areal interpolation to census areas](https://dosull.github.io/dulux-colours-map/maps/areal-interpolation.html) using `sf::st_interpolate_aw`

The R code used to make the maps can be viewed [here](code/build-dulux-colours-map.md).

Running the code will produce quite a few data files, which are _not_ posted here.

The annotated output of the [RMarkdown](https://rmarkdown.rstudio.com/) of the code can be [viewed here](https://dosull.github.io/dulux-colours-map/code/). This was lightly modified to make [these slides](https://dosull.github.io/dulux-colours-map/slides/) for a Maptime! presentation in September 2021.

**Note that as I continue to learn more about the various R packages used here the code will continue to be tweaked. For the record the [version of the slideshow presented at Maptime! on 22 September 2021 is here](https://dosull.github.io/dulux-colours-map/slides/maptime-slides.html).**

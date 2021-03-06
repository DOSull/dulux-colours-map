---
title: "Mapping the Dulux colours of New Zealand using R"
author: "David O'Sullivan"
date: September 2021
output: html_document
---

# Libraries
We need a bunch of these...

## JSON processing
First `jsonlite` for processing the colours data pulled from the website

```{r}
library(jsonlite)
```

## Data wrangling
Next, a bunch of data munging packages from the 'tidyverse'

```{r}
library(tidyr)
library(plyr) # rbind.fill useful for ragged data with missing entries
library(dplyr)  
library(magrittr)
library(tibble)
library(stringr)
```

## Spatial
Next, the basic R spatial packages

```{r}
library(sf)
library(raster)
library(tmap)
library(tmaptools) # for geocode_OSM
tmap_mode("view") # for web maps
```

## Interpolation
Finally, a range of interpolation tools

```{r}
library(spatstat) # for IDW
library(maptools)
library(akima)    # for triangulation
library(fields)   # for splines
```

# Getting the colours

See [the Dulux website](https://www.dulux.co.nz/colour/colours-of-new-zealand) for what this is all about

First I had a poke around on the website to figure out where the colour details were to be found

```{r}
colour_groups <- c("blues", "browns", "greens", "greys", "oranges",
                  "purples", "reds", "whites-neutrals", "yellows")
base_url <- "https://www.dulux.co.nz/content/duluxnz/home/colour/all-colours.categorycolour.json/all-colours/"
```

## Retrieve and save the colours
The loop on the next slide

+ steps through the group names
+ retrieves the relevant JSON file
+ writes it out locally
+ adds the colours information to a list
+ then we make the list into a single table using `bind_rows`

***

```{r eval = FALSE}
colours <- list()
for (i in 1:length(colour_groups)) {
  colour_group <- colour_groups[i]
  json_url <- str_c(base_url, colour_group)
  json <- fromJSON(json_url, flatten = TRUE)
  # make a local copy (just for convenience)
  json_file_name <- str_c(colour_group, ".json")
  write_json(json, json_file_name)
  # get the colours information and add to list
  the_colours <- rbind.fill(json$categoryColours$masterColour.colours)
  colours[[i]] <- the_colours
  Sys.sleep(0.5) # pause to not annoy the the server  
}
df_colours <- bind_rows(colours)
write.csv(df_colours, "dulux-colours-raw.csv", row.names = FALSE)
```

## Check we're all good
```{r echo = FALSE}
df_colours <- read.csv("dulux-colours-raw.csv")
```

```{r}
head(df_colours)
```

# Tidying up the names
There are paint names with modifiers as suffixes for different shades of particular colours, and we need to handle this

The modifiers are
```{r}
paint_modifiers <- c("Half", "Quarter", "Double")
```

## A _tidyverse_ pipeline
Here???s one way to clean this up (there are others???)

```{r eval = FALSE}
df_colours_tidied <- df_colours %>%
  ## separate the name components, filling from the left with NAs if <5
  separate(name, into = c("p1", "p2", "p3", "p4", "p5"), sep = " ",
           remove = FALSE, fill = "left") %>%
  ## replace any NAs with an empty string
  mutate(p1 = str_replace_na(p1, ""),
         p2 = str_replace_na(p2, ""),
         p3 = str_replace_na(p3, ""),
         p4 = str_replace_na(p4, "")) %>%
  ## if p5 is a paint modifiers, then recompose name
  ## from p1:p4 else from p1:p5
  ## similarly keep modifier where it exists
  mutate(placename = if_else(p5 %in% paint_modifiers,
                       str_trim(str_c(p1, p2, p3, p4, sep = " ")),
                       str_trim(str_c(p1, p2, p3, p4, p5, sep = " "))),
         modifier = if_else(p5 %in% paint_modifiers,
                       p5, "")) %>%
  ## remove some places that are tricky to deal with later
  filter(!placename %in% c("Chatham Islands",
                           "Passage Rock",
                           "Auckland Islands",
                           "Cossack Rock")) %>%
  ## throw away variables we no longer need and reorder
  select(name, placename, modifier, red, green, blue)

# save it so we have it for later
write.csv(df_colours_tidied, "dulux-colours.csv", row.names = FALSE)
```

# Build the spatial dataset
Add `x` and `y` columns to our data for the coordinates

```{r echo = FALSE}
df_colours_tidied <- read.csv("dulux-colours.csv")
```

```{r}
df_colours_tidied_xy <- df_colours_tidied %>%
  mutate(x = 0, y = 0)
```

## Geocode with `tmaptools::geocode_OSM`
Code on the next slide

+ goes through all the unique placenames
+ appends as many `x` `y` coordinates as we have space for (due to the modifiers) from the geocoding results

***

**Best not to re-run this (it takes a good 10 minutes and it's not good to repeatedly geocode and hit the OSM server)**

```{r eval = FALSE}
for (placename in unique(df_colours_tidied_xy$placename)) {
  address <- str_c(placename, "New Zealand", sep = ", ")
  geocode <- geocode_OSM(address, as.data.frame = TRUE,
                         return.first.only = FALSE)
  num_geocodes <- nrow(geocode)
  matching_rows <- which(df_colours_tidied_xy$placename == placename)
  for (i in 1:length(matching_rows)) {
    if (!is.null(geocode)) {
      if (num_geocodes >= i) {
        df_colours_tidied_xy[matching_rows[i], ]$x <- geocode$lon[i]
        df_colours_tidied_xy[matching_rows[i], ]$y <- geocode$lat[i]
      }  
    }
  }
  Sys.sleep(0.5) # so as not to over-tax the geocoder
}
# Remove any we missed
df_colours_tidied_xy <- df_colours_tidied_xy %>%
  filter(x != 0 & y != 0)

write.csv(df_colours_tidied_xy, "dulux-colours-xy.csv", row.names = FALSE)
```

# Making maps

```{r echo = FALSE}
df_colours_tidied_xy <- read.csv("dulux-colours-xy.csv")
```

Make the dataframe into a `sf` point dataset

```{r eval = FALSE}
dulux_colours_sf <- df_colours_tidied_xy %>%
  st_as_sf(coords = c("x", "y"), ## columns with the coordinates
           crs = 4326) %>%       ## EPSG:4326 for lng-lat
  st_transform(2193) %>%         ## convert to NZTM
  ## and make an RGB column
  mutate(rgb = rgb(red / 255, green / 255, blue/ 255))

# jitter any duplicate locations
duplicate_pts <- which(duplicated(dulux_colours_sf$geometry) |
                       duplicated(dulux_colours_sf$geometry,
                                  fromLast = TRUE))
jittered_pts <- dulux_colours_sf %>%
  slice(duplicate_pts) %>%
  st_jitter(50)
dulux_colours_sf[duplicate_pts, ]$geometry <- jittered_pts$geometry

st_write(dulux_colours_sf, "dulux-colours-pts.gpkg", delete_dsn = TRUE)
```

Update the dataframe of points with the jittered points

```{r eval = FALSE}
jittered_pts <- dulux_colours_sf %>%
  st_coordinates() %>%
  as_tibble()
df_colours_tidied_xy <- df_colours_tidied_xy %>%
  mutate(x = jittered_pts$X, y = jittered_pts$Y)
write.csv(df_colours_tidied_xy, "dulux-colours-xy-jit.csv", row.names = TRUE)
```

## And at last a map!

```{r}
nz <- st_read("nz.gpkg")
```

```{r echo = FALSE}
dulux_colours_sf <- st_read("dulux-colours-pts.gpkg")
df_colours_tidied_xy <- read.csv("dulux-colours-xy-jit.csv")
```

Using the `tmap` package

```{r}
tm_shape(nz) +
  tm_borders() +
  tm_shape(dulux_colours_sf) +
  tm_dots(col = "rgb")
```

# We can do better (depending on taste!)
Points aren't really much fun, instead:

+ [Voronoi polygons](#voronoi-polygons)
+ [Triangular facets](#triangulation)
+ [Inverse-distance weighted](#idw)
+ [Splines](#splines)
+ [Areal interpolation to SA2s](#areal-interpolation)

# Voronoi polygons
We can make Voronois and clip to NZ

```{r eval = FALSE}
dulux_colours_vor <- dulux_colours_sf %>%
  st_union() %>%
  st_voronoi() %>%
  st_cast() %>%
  st_as_sf() %>%
  st_join(dulux_colours_sf, left = FALSE) %>%
  st_intersection(st_read("nz.gpkg"))

st_write(dulux_colours_vor, "dulux-colours-vor.gpkg", delete_dsn = TRUE)
```

## And map

```{r echo = FALSE}
dulux_colours_vor <- st_read("dulux-colours-vor.gpkg")
```

```{r}
tm_shape(dulux_colours_vor) +
  tm_polygons(alpha = 0, border.col = "lightgrey", lwd = 0.5) +
  tm_shape(dulux_colours_vor) +
  tm_polygons(col = "rgb", id = "placename",
              alpha = 0.75, border.col = "grey", lwd = 0.2)
```

# Triangulation
Using the `akima::interp` package

```{r eval = FALSE}
components = c("red", "green", "blue")

layers = list()
for (component in components) {
  # the dimensions, nx, ny give ~500m resolution
  layers[[component]] <- raster(
    interp(df_colours_tidied_xy$x, df_colours_tidied_xy$y,
           df_colours_tidied_xy[[component]],
           nx = 2010, ny = 2955, linear = TRUE))
}
rgb.t <- brick(layers)
crs(rgb.t) <- st_crs(nz)$wkt
rgb.t <- mask(rgb.t, nz)

writeRaster(rgb.t, "dulux-colours-tri.tif", overwrite = TRUE)
```

## And map

```{r echo = FALSE}
rgb.t <- raster("dulux-colours-tri.tif")
```

```{r}
tm_shape(dulux_colours_vor) +
  tm_polygons(alpha = 0, border.col = "lightgrey", lwd = 0.5) +
  tm_shape(rgb.t) +
  tm_rgb()
```

# IDW
Here we use the `spatstat::idw` function

We have to make `spatstat::ppp` (point pattern) objects

```{r eval = FALSE}
## We need a window for the ppps
W <- nz %>%
  st_geometry() %>%
  st_buffer(1000) %>%
  st_union() %>%
  as("Spatial") %>%
  as.owin()

layers <- list()
for (component in components) {
  pp <- ppp(x = df_colours_tidied_xy$x,
            y = df_colours_tidied_xy$y,
            window = W,
            marks = df_colours_tidied_xy[[component]])
  ## eps is the approximate resolution
  layers[[component]] <- raster(idw(pp, eps = 2500, power = 4))
}
rgb.idw <- brick(layers)
crs(rgb.idw) <- st_crs(nz)$wkt

writeRaster(rgb.idw, "dulux-colours-idw.tif", overwrite = TRUE)
```

## And map

```{r echo = FALSE}
rgb.idw <- raster("dulux-colours-idw.tif")
```

```{r}
tm_shape(dulux_colours_vor) +
  tm_polygons(alpha = 0, border.col = "lightgrey", lwd = 0.5) +
  tm_shape(rgb.idw) +
  tm_rgb()
```

# Splines
For this we use the `fields::Tps` (thin plate spline) function

We need an empty raster to interpolate into

```{r eval = FALSE}
r <- nz %>%
  raster(resolution = 2500)
```

***

Then we can interpolate as before

```{r eval = FALSE}
layers <- list()
for (component in components) {
  spline <- Tps(df_colours_tidied_xy[, c("x", "y")],
                df_colours_tidied_xy[[component]],
                scale.type = "unscaled", m = 3)
  layers[[component]] <- interpolate(r, spline)
}
rgb.s <- brick(layers)
crs(rgb.s) <- st_crs(nz)$wkt
rgb.s <- mask(rgb.s, nz)

writeRaster(rgb.s, "dulux-colours-spline.tif", overwrite = TRUE)
```

## And map

```{r echo = FALSE}
rgb.s <- raster("dulux-colours-spline.tif", overwrite = TRUE)
```

```{r}
tm_shape(dulux_colours_vor) +
  tm_polygons(alpha = 0, border.col = "lightgrey", lwd = 0.5) +
  tm_shape(rgb.s) +
  tm_rgb()
```

## Areal interpolation

We can also do weighted mixing by areas of overlap with any other set of areas from the Voronois.

```{r eval = FALSE}
sa2 <- st_read("sa2-generalised.gpkg")

dulux_colours_sa2 <- dulux_colours_vor %>%
  select(red:blue) %>%
  st_interpolate_aw(sa2, extensive = FALSE) %>%
  mutate(rgb = rgb(red / 256, green / 256, blue / 256),
         name = sa2$SA22018_V1_00_NAME)

st_write(dulux_colours_sa2, "dulux-colours-sa2.gpkg", delete_dsn = TRUE)
```

## And map

```{r echo = FALSE}
dulux_colours_sa2 <- st_read("dulux-colours-sa2.gpkg")
```

```{r}
tm_shape(dulux_colours_vor) +
  tm_fill(col = "rgb", id = "placename") +
  tm_shape(dulux_colours_sa2) +
  tm_polygons(col = "rgb", id = "name", border.col = "white", lwd = 0.2)
```

# Credits and more

+ Maptime!
+ See [github.com/DOSull/dulux-colours-map](https://github.com/DOSull/dulux-colours-map) for the code
+ See the same place for other odds and ends I do (including my classes at Vic!)
+ All the amazing people behind:
    + _R_ and _RStudio_
    + `sf` and `tmap` (for basic geospatial)
    + the _tidyverse_ packages
    + _RMarkdown_

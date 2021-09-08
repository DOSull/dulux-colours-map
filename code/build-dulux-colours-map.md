---
title: "A web map of the Dulux colours of New Zealand"
output: html_document
---

# Build a web map of the Dulux colours of New Zealand

## Libraries

We need a bunch of these. First `jsonlite` for processing the colours data pulled from the website.

```{r message = FALSE}
library(jsonlite) # for processing the JSON files of colours
```

Next, a bunch of data munging packages from the tidyverse.

```{r message = FALSE}
library(plyr)     # rbind.fill is super useful for ragged data with missing rows
library(dplyr)  
library(magrittr)
library(tibble)
library(stringr) 
```

And finally R spatial packages.

```{r message = FALSE}
library(sf)
library(tmap)
library(tmaptools) # geocoding
```

## Getting the colours

See [this website](https://www.dulux.co.nz/colour/colours-of-new-zealand) for what this is all about. Prior to building this notebook I had a poke around on the website to figure out where the colour details were to be found.

```{r}
colour_groups <- c("blues", "browns", "greens", "greys", "oranges",
                  "purples", "reds", "whites-neutrals", "yellows")
base_url <- "https://www.dulux.co.nz/content/duluxnz/home/colour/all-colours.categorycolour.json/all-colours/"
colour_sets <- str_c(base_url, colour_groups)
```

The loop below, steps through the group names, retrieves the relevant JSON file from the web, writes it out locally, and parses the key information into a data table.

```{r eval = FALSE}
df_colours <- NULL
for (group in colour_groups) {
  source <- str_c(base_url, group)
  file_name <- str_c(group, ".json")
  json <- fromJSON(source, flatten = TRUE)
  write_json(json, file_name)
  the_colours <- rbind.fill(json$categoryColours$masterColour.colours)
  if (is.null(df_colours)) {
    df_colours <- the_colours
  } else {
    df_colours <- bind_rows(df_colours, the_colours)
  }
  Sys.sleep(0.5)  
}
write.csv(df_colours, "dulux-colours-raw.csv", row.names = FALSE)
```

We can check what we got

```{r}
df_colours <- read.csv("dulux-colours-raw.csv")
head(df_colours)
```

## Tidying up the names
There are paints with various modifiers as suffixes to specify slightly different shades of particular colours.

```{r}
paint_modifiers <- c("Half", "Quarter", "Double")
```

A tidy pipeline is a nice way to clean this up. There are other ways (like writing a function, but it's nice to show it using just built-in tidy operations).

```{r eval = FALSE}
df_colours_tidied <- df_colours %>%
  ## remove some columns we won't be needing
  select(-id, -baseId, -woodType, -coats) %>%
  ## separate the name components, filling from the left with NAs if <5
  separate(name, into = c("p1", "p2", "p3", "p4", "p5"), sep = " ", 
           remove = FALSE, fill = "left") %>%
  ## replace any NAs with an empty string
  mutate(p1 = str_replace_na(p1, ""),
         p2 = str_replace_na(p2, ""),
         p3 = str_replace_na(p3, ""),
         p4 = str_replace_na(p4, "")) %>%
  ## if p5 is a paint modifiers, then recompose name from p1:p4 else from p1:p5
  ## similarly keep modifier where it exists
  mutate(placename = if_else(p5 %in% paint_modifiers, 
                             str_trim(str_c(p1, p2, p3, p4, sep = " ")), 
                             str_trim(str_c(p1, p2, p3, p4, p5, sep = " "))),
         modifier = if_else(p5 %in% paint_modifiers, 
                            p5, "")) %>%
  ## remove some places that are kind of awkward to deal with later
  filter(!placename %in% c("Chatham Islands", "Passage Rock", "Auckland Islands", "Cossack Rock")) %>%
  ## throw away variables we no longer and reorder
  select(name, placename, modifier, red, green, blue)

# save it so we have it for later
write.csv(df_colours_tidied, "dulux-colours.csv", row.names = FALSE)
```

## Build the spatial dataset

Add x and y columns to our data for the coordinates - note that we re-load from the saved file so as not to repeat hitting the Dulux website.

```{r}
df_colours_tidied <- read.csv("dulux-colours.csv")
df_colours_tidied_xy <- df_colours_tidied %>%
  mutate(x = 0, y = 0)
```

Go through all the unique names, and append as many x y coordinates as we have space for (due to the modifiers) from the geocoding results.

**In general best not to re-run this (it takes a good 10 minutes and it's not good to repeatedly re-geocode and hit the OSM server).**

```{r eval = FALSE}
for (placename in unique(df_colours_tidied_xy$placename)) {
  address <- str_c(placename, "New Zealand", sep = ", ")
  geocode <- geocode_OSM(address, as.data.frame = TRUE, return.first.only = FALSE)
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
```

Do another tidy up removing anything that didn't get geocoded.

```{r eval = FALSE}
df_colours_tidied_xy <- df_colours_tidied_xy %>%
  filter(x != 0 & y != 0)

write.csv(df_colours_tidied_xy, "dulux-colours-xy.csv", row.names = FALSE)
```

## Making a map
Get the geocoded dataset we made earlier.

```{r}
dulux_colours <- read.csv("dulux-colours-xy.csv")
```

Now make it into an `sf` point dataset

```{r}
dulux_colours_sf <- st_as_sf(dulux_colours, coords = c("x", "y"), crs = 4326) %>%
  st_transform(2193) %>%
  mutate(rgb = rgb(red / 255, 
                   green / 255, 
                   blue/ 255))

st_write(dulux_colours_sf, "dulux-colours-pts.gpkg", delete_dsn = TRUE)
```

And at last a map!

```{r}
tmap_mode("view")
tm_shape(dulux_colours_sf) + 
  tm_dots()
```

## Better yet, Voronois

Now make up voronois and clip to NZ.

```{r}
dulux_colours_vor <- dulux_colours_sf %>%
  st_union() %>%
  st_voronoi() %>%
  st_cast() %>%
  st_as_sf() %>%
  st_join(dulux_colours_sf, left = FALSE) %>%
  st_intersection(st_read("nz.gpkg")) 

st_write(dulux_colours_vor, "dulux-colours-vor.gpkg", delete_dsn = TRUE)
```

And map it

```{r}
tm_shape(dulux_colours_vor) + 
  tm_polygons(col = "rgb", id = "placename", alpha = 0.75, border.col = "grey", lwd = 0.2) +
  tm_basemap("Esri.WorldTopoMap")
```
library(sf)
library(raster)
library(dplyr)
library(tidyr)
library(stringr)
library(data.table)

setwd("~/Documents/code/dulux-colours-map")

get_CMYK <- Vectorize(function(R, G, B) {
  Rn <- R / 255
  Gn <- G / 255
  Bn <- B / 255
  K <- 1 - max(Rn, Gn, Bn)
  C <- ifelse(K == 1, 0, (1 - Rn - K) / (1 - K))
  M <- ifelse(K == 1, 0, (1 - Gn - K) / (1 - K))
  Y <- ifelse(K == 1, 0, (1 - Bn - K) / (1 - K))
  return(list(C = C, M = M, Y = Y, K = K));
})

get_RGB <- Vectorize(function(C, M, Y, K, component = "red") {
  if (component == "red") {
    return(255 * (1 - C) * (1 - K))
  }
  if (component == "green") {
    return(255 * (1 - M) * (1 - K))
  }
  return(255 * (1 - Y) * (1 - K))
})


nz <- st_read("nz.gpkg")

r <- nz %>% 
  st_make_grid(cellsize = 5000, what = "centers") %>%
  st_coordinates() %>%
  as_tibble() %>%
  mutate(Z = 0) %>%
  rasterFromXYZ()

dulux_pts <- st_read("dulux-colours-pts.gpkg")

rgb <- dulux_pts %>%
  st_coordinates() %>%
  as_tibble() %>%
  mutate(red = dulux_pts$red, green = dulux_pts$green, blue = dulux_pts$blue) %>%
  mutate(cyan = 0, magenta = 0, yellow = 0, black = 0)

## NO IDEA WHY THIS IS SO ARCANE!
rgb[, c("cyan", "magenta", "yellow", "black")] <- as_tibble(t(get_CMYK(rgb$red, rgb$green, rgb$blue)))
rgb <- rgb %>%
  mutate(across(where(is.list), as.numeric))

library(fields)

components <- c("cyan", "magenta", "yellow", "black")
layers <- list()
for (component in components) {
  spline <- Tps(rgb[, 1:2], rgb[[component]], scale.type = "unscaled")
  layers[[component]] <- interpolate(r, spline)
}
spline_cmyk <- brick(layers)


library(tmap)
tmap_mode("view")

tm_shape(spline_rgb) + 
  tm_rgb() +
  tm_shape(nz) + 
  tm_borders(col = "blue", lwd = 0.1)
  
library(spatstat)
library(maptools)

W <- nz$geom %>%
  st_buffer(1000) %>%
  st_union() %>%
  as("Spatial") %>%
  as.owin()
 
layers <- list()
for (component in components) {
  pp <- ppp(x = rgb$X, y = rgb$Y, window = W, marks = rgb[[component]])
  layers[[component]] <- raster(idw(pp, eps = 2500, power = 4))
}
idw.rgb <- brick(layers)
crs(idw.rgb) <- st_crs(nz)$wkt

tm_shape(idw.rgb) +
  tm_rgb() + 
  tm_shape(nz) + 
  tm_borders(col = "blue", lwd = 0.1)
  # tm_shape(dulux_pts) +
  # tm_dots(col = "rgb")

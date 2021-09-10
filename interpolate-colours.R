library(sf)
library(raster)
library(dplyr)
library(tidyr)
library(stringr)
library(fields)
library(tmap)
tmap_mode("plot")
library(spatstat)
library(maptools)
library(akima)

setwd("~/Documents/code/dulux-colours-map")


get_rescale <- function(r1, r2) {
  range1 <- r1[2] - r1[1]
  range2 <- r2[2] - r2[1]
  scale <- range2 / range1
  return (function(x) {
    return(r2[1] + scale * (x - r1[1]))
  })
}


nz <- st_read("nz.gpkg")

r <- nz %>% 
  st_make_grid(cellsize = 2500, what = "centers") %>%
  st_coordinates() %>%
  as_tibble() %>%
  rename(x = X, y = Y) %>%
  mutate(z = 0) %>%
  rasterFromXYZ()

dulux_pts <- st_read("dulux-colours-pts.gpkg")

rgb <- dulux_pts %>%
  st_coordinates() %>%
  as_tibble() %>%
  # rename(x = X, y = Y) %>%
  mutate(red = dulux_pts$red, green = dulux_pts$green, blue = dulux_pts$blue)

components <- c("red", "green", "blue")
layers <- list()
for (component in components) {
  spline <- Tps(rgb[, 1:2], rgb[[component]], scale.type = "unscaled", m = 3)
  layers[[component]] <- interpolate(r, spline)
}
rgb.s <- brick(layers)
crs(rgb.s) <- st_crs(nz)$wkt
rgb.s <- mask(rgb.s, nz)

rgb.s$red <- get_rescale(c(minValue(rgb.s$red), maxValue(rgb.s)), 
                         range(rgb$red))(rgb.s$red)
rgb.s$green <- get_rescale(c(minValue(rgb.s$green), maxValue(rgb.s$green)), 
                           range(rgb$green))(rgb.s$green)
rgb.s$blue <- get_rescale(c(minValue(rgb.s$blue), maxValue(rgb.s$blue)), 
                          range(rgb$blue))(rgb.s$blue)


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
rgb.idw <- brick(layers)
crs(rgb.idw) <- st_crs(nz)$wkt

vor <- st_read("dulux-colours-vor.gpkg")

m1 <- tm_shape(vor) + 
  tm_polygons(col = "rgb", border.col = "grey", lwd = 0.1) +
  tm_layout(title = "Voronoi")
m2 <- tm_shape(rgb.idw) +
  tm_rgb() +
  tm_layout(title = "IDW of rgb")
m3 <- tm_shape(rgb.s) +
  tm_rgb() + 
  tm_layout(title = "Spline of rgb")

tmap_arrange(m1, m2, m3, nrow = 1)


tri.r <- interp(rgb$X, rgb$Y, rgb$red,
                nx = 402, ny = 591, linear = TRUE)
tri.g <- interp(rgb$X, rgb$Y, rgb$green,
                nx = 402, ny = 591, linear = TRUE)
tri.b <- interp(rgb$X, rgb$Y, rgb$blue,
                nx = 402, ny = 591, linear = TRUE)

rgb.t <- brick(list(red = raster(tri.r), 
                    green = raster(tri.g), 
                    blue = raster(tri.b)))
crs(rgb.t) <- st_crs(nz)$wkt
rgb.t <- mask(rgb.t, nz)

tm_shape(rgb.t) + 
  tm_rgb()


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

get_R <- Vectorize(function(C, M, Y, K) {
  return(255 * (1 - C) * (1 - K))
})
get_G <- Vectorize(function(C, M, Y, K) {
  return(255 * (1 - M) * (1 - K))
})
get_B <- Vectorize(function(C, M, Y, K) {
  return(255 * (1 - Y) * (1 - K))
})


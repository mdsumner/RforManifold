#' ODBC connection to Manifold map files.
#' 
#' Create an ODBC connection for Manifold GIS. 
#' 
#' See \code{\link[RODBC]{odbcDriverConnect}}
#' @param mapfile character string, path to Manifold project *.map file
#' @param unicode logical
#' @param ansi logical
#' @param opengis logical
#' @details See the documentation for the underlying driver:
#' \url{http://www.georeference.org/doc/using_the_manifold_odbc_driver.htm}
#' Be sure to set ansi = FALSE for some string escape cases like CoordSys("Drawing" AS COMPONENT). 
#' @examples
#' \dontrun{
#' f <- system.file("extdata", "AreaDrawing.map", package = "manifoldr")
#' con <- odbcConnectManifold(f)
#' tab <- RODBC::sqlQuery(con, "SELECT * FROM [Drawing]")
#' ## drop [Geom (I)] and give a summary
#' summary(subset(tab, select = -`Geom (I)`))
#' 
#' ## issue a spatial query
#' qtx <- "SELECT [ID], [Name], [Length (I)] AS [Perim], 
#'      BranchCount([ID]) AS [nbranches] FROM [Drawing Table]"
#' sq <- RODBC::sqlQuery(con, qtx)
#' sq
#' }
#' @return RODBC object
#' @importFrom RODBC odbcDriverConnect
#' @importFrom tools toTitleCase 
#' @export
odbcConnectManifold <- function (mapfile, unicode = TRUE, ansi = FALSE, opengis = TRUE)
  
{
  
  full.path <- function(filename) {
    
    fn <- chartr("\\", "/", filename)
    
    is.abs <- length(grep("^[A-Za-z]:|/", fn)) > 0
    
    chartr("/", "\\", if (!is.abs)
      
      file.path(getwd(), filename)
      
      else filename)
    
  }
  unicode <- tools::toTitleCase(tolower(format(unicode)))
  ansi <- tools::toTitleCase(tolower(format(ansi)))
  opengis <- tools::toTitleCase(tolower(format(opengis)))
  
  parms <- sprintf(";Unicode=%s;Ansi=%s;OpenGIS=%s;DSN=Default", unicode, ansi, opengis)
  
  con <- if (missing(mapfile))
    
    "Driver={Manifold Project Driver (*.map)};Dbq="
  
  else {
    
    fp <- full.path(mapfile)
    
    paste("Driver={Manifold Project Driver (*.map)};DBQ=",
          
          fp, ";DefaultDir=", dirname(fp), parms, ";", sep = "")
    
  }
RODBC::odbcDriverConnect(con)
  
}


.cleanup <- function(x) {
  if (x > -1) RODBC::odbcClose(x)
  invisible(NULL)
}

topolclause <- function(x) {
  switch(x, 
         area = "IsArea([ID])", 
         line = "IsLine([ID])", 
         point = "IsPoint([ID])")
}

#' @importFrom wkb readWKB
#' @importFrom sp CRS proj4string<- SpatialPolygonsDataFrame SpatialLinesDataFrame SpatialPointsDataFrame
readmfd <- function(dsn, table, query = NULL, spatial = FALSE, topol = c("area", "line", "point")) {

  topol <- match.arg(topol)
  on.exit(.cleanup(con))
 # if (!checkAvailability()) {stop("Manifold is not installed, but is required for connection to project files.")}
  con <- odbcConnectManifold(dsn)
  atts <- "*"
  if (spatial) {
    
    #mc <- mapcontents(dsn)
    attributes <- columnames(con, table)
    #mc$columns$colnames[mc$columns$tableID == mc$tables$ID[which(mc$tables$TABLE_NAME == table)]]
   
    attributes <- 
      paste0("[", attributes[-grep(" \\(I\\)", attributes)], "]")
  #  print(attributes)
    randomstring <- paste(sample(c(letters, 1:9), 15, replace = TRUE), collapse = "")
    atts <- sprintf("%s, CGeomWKB(Geom(ID)) AS [%s]", paste(attributes, collapse = ","), randomstring)
    crswkt <- manifoldCRS(con, table)
    crs <- wktCRS2proj4(crswkt)
   # print(crswkt)
  #  print(crs)
  }
  if (is.null(query)) {
    query <- sprintf("SELECT %s FROM [%s] WHERE %s", atts, table, topolclause(topol))
  }
#  print(query)
  
  #return(query)
 x <-  RODBC::sqlQuery(con, query)
 if (spatial) {
   if (nrow(x) < 1L) stop("query returned no records, cannot create a Spatial object from this")
   geom <- wkb::readWKB(x[[randomstring]])
   proj4string(geom) <-  CRS(crs)
  # print(geom)
   x[[randomstring]] <- NULL
   ## reconstruct our original layer
   x <- switch(topol, 
                area = SpatialPolygonsDataFrame(geom, x, match.ID = FALSE), 
                line = SpatialLinesDataFrame(geom, x, match.ID = FALSE), 
                point = SpatialPointsDataFrame(geom, x, match.ID = FALSE))
   
 }
 x
}



#' Read a Drawing from a Manifold project. 
#'
#' @param mapfile Manifold project file
#' @param dwgname Drawing name to read
#'
#' @return drawingA returns a 'SpatialPolygonsDataFrame', drawingL a 'SpatialLinesDataFrame' and drawingP a 'SpatialPointsDataFrame'
#' @export
#' 
#' @examples
#' mapfile <- system.file("extdata", "AreaDrawing.map", package = "manifoldr")
#' geom2D <- DrawingA(mapfile, "Drawing")
#' geom2D
#' 
#' geom1D <- DrawingL(mapfile, "Drawing")
#' geom1D
#' 
#' geom0D <- DrawingP(mapfile, "Drawing")
#' geom0D
DrawingA <- function(mapfile, dwgname) {

  readmfd(mapfile, dwgname, topol = "area", spatial = TRUE)
}


#' @rdname DrawingA
#' @export
DrawingL <- function(mapfile, dwgname) {
  readmfd(mapfile, dwgname, topol = "line", spatial = TRUE)
}

#' @rdname DrawingA
#' @export
DrawingP <- function(mapfile, dwgname) {
  readmfd(mapfile, dwgname, topol = "point", spatial = TRUE)
}

rasterFromManifoldGeoref <- function(x, crs) {
  ex <- extent(x$xmin,  x$xmin + x$ncol * x$dx,
               x$ymax - (x$nrow - 1) * x$dy,
               x$ymax + x$dy)
  raster(ex, nrow = x$nrow, ncol = x$ncol, crs = crs)
}


#' Read a Surface from a Manifold project file. 
#'
#' @param mapfile Manifold project file
#' @param rastername Surface name to read 
#'
#' @return RasterLayer
#' @export
#'
#' @examples
#' mapfile2 <- system.file("extdata", "Montara_20m.map", package= "manifoldr")
#' gg <- Surface(mapfile2, "Montara")
#' @importFrom raster extent ncol nrow raster setValues
Surface <- function(mapfile, rastername) {
  if (!requireNamespace("raster", quietly = TRUE)) {
    stop("raster package not available, please install it with install.packages(\"raster\")")
  } else {
    if (!"raster" %in% .packages()) {
      if (interactive()) {warning("raster package is loaded but not attached, you'll need to run library(\"raster\") to use it") }
    }
  }
  on.exit(.cleanup(con))
  # if (!checkAvailability()) {stop("Manifold is not installed, but is required for connection to project files.")}
  con <- odbcConnectManifold(mapfile)
  
  row1 <- sqlQuery(con, sprintf("SELECT TOP 1 * FROM [%s]", rastername))
  zz <- sqlQuery(con, sprintf("SELECT [Height (I)] FROM [%s]", rastername))
georef <- getGeoref(con, rastername)
crswkt <- manifoldCRS(con, rastername)
#print(crswkt)
  crs <- wktCRS2proj4(crswkt)
#  print(crs)
#crs <- NA_character_
  setValues(rasterFromManifoldGeoref(georef, crs), zz$`Height (I)`)
}


getGeoref <- function(con, rastername) {
  sqlQuery(con, sprintf("SELECT TOP 1 [Easting (I)] AS [xmin],  [Northing (I)] AS [ymax], PixelsByX([%s]) AS [ncol], PixelsByY([%s]) AS [nrow], 
                        PixelWidth([%s]) AS [dx], PixelHeight([%s]) AS [dy] FROM [%s]", rastername, rastername, rastername, rastername, rastername))
}
columnames <- function(con, tablename) {
  names(sqlQuery(con, sprintf("SELECT * FROM [%s] WHERE 0 = 1", tablename)))
}
mapcontents <- function(mapfile) {
  on.exit(.cleanup(con))
  con <- odbcConnectManifold(mapfile)
  if (con < 0) stop(sprintf('cannot open %s\nRODBC warning messages:\n\n', mapfile))
  tabs <- RODBC::sqlTables(con)
  tabs$ID <- seq(nrow(tabs))
  cols <- vector("list", nrow(tabs))
  # print(names(tabs))
  for (itab in seq_along(tabs$TABLE_NAME)) {
    tab <- sqlQuery(con, sprintf("SELECT * FROM [%s] WHERE 0 = 1", tabs$TABLE_NAME[itab]), as.is = TRUE)
    # print(tab)
    # print(list(colnames = names(tab), table = tabs$TABLE_NAME[itab]))
    # 
    cols[[itab]] <- data.frame(colnames = names(tab), tableID = tabs$ID[itab], stringsAsFactors = FALSE)
  }
  list(tables = tabs, columns = do.call(rbind, cols))
}

#' @importFrom RODBC sqlQuery
manifoldCRS <- function(connection, componentname) {
  qu <- sprintf('SELECT TOP 1 CoordSysToWKT(CoordSys(\"%s\" AS COMPONENT)) AS [CRS] FROM [%s]',  
                componentname, 
                componentname)
  RODBC::sqlQuery(connection, qu, stringsAsFactors = FALSE)$CRS
}

#' #' @importFrom RODBC sqlQuery
#' manifoldDrawingCRS <- function(connection, componentname) {
#'    qu <- sprintf('SELECT TOP 1 CoordSysToWKT(CCoordSys([Geom (I)])) AS [CRS] FROM [%s]',  componentname)
#'   RODBC::sqlQuery(connection, qu, stringsAsFactors = FALSE)$CRS
#' }
#' 
#' #' @importFrom RODBC sqlQuery
#' manifoldRasterCRS <- function(connection, componentname) {
#'   ## this should work but does not
#'   ##qu <- sprintf('SELECT TOP 1 CoordSysToWKT(CoordSys("%s" AS COMPONENT)) AS [CRS] FROM [%s]', componentname, componentname)
#'  # TOP 1 CCoordSys(NewPoint([Easting (I)], [Northing (I)]))
#'   qu <- sprintf('OPTIONS COORDSYS("[%s]" AS COMPONENT);SELECT TOP 1 CoordSysToWKT(CCoordSys(NewPoint([Easting (I)], [Northing (I)]))) AS [CRS] FROM [%s];',  componentname, componentname)
#'   #print(qu)
#'   RODBC::sqlQuery(connection, qu, stringsAsFactors = FALSE)$CRS
#' }

#' @rawNamespace 
#' if ( packageVersion("rgdal") >= "1.1.4") {
#' importFrom("rgdal", showP4)
#' }
#' @importFrom utils packageVersion
#' @importFrom rgdal writeOGR readOGR
#' @importFrom sp proj4string SpatialPoints SpatialPointsDataFrame
wktCRS2proj4 <- function(CRS) {

  if ( packageVersion("rgdal") >= "1.1.4") {
    return(rgdal::showP4(CRS))
  }
  dsn <- tempdir()
  f <- basename(tempfile())
  writeOGR(SpatialPointsDataFrame(SpatialPoints(cbind(1, 1)), data.frame(x = 1)), dsn, f, "ESRI Shapefile", overwrite_layer = TRUE)
  writeLines(CRS, paste(file.path(dsn, f), ".prj", sep = ""))
  proj4 <- proj4string(readOGR(dsn, f, verbose = FALSE))
  proj4
  
}

#' @importFrom methods is
#' @importFrom rgeos readWKT
#' @importFrom maptools spRbind
#' @importFrom sp SpatialPolygonsDataFrame
wkt2Spatial <- function(x, id = NULL, p4s = NULL, data = data.frame(x = 1:length(x), row.names = id), ...) {
  if (is.null(id)) id <- as.character(seq_along(x))
  for (i in seq_along(x)) {
    a1 <- rgeos::readWKT(x[i], id = id[i], p4s = p4s)
    if (i == 1) {
      res <- a1
    } else {
      res <- maptools::spRbind(res, a1)
    }
  }
  if (is(res, "SpatialPolygons")) {
    res <- sp::SpatialPolygonsDataFrame(res, data, ...)
  }
  
  res
}

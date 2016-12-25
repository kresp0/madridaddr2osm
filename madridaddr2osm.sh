# Download, reproject and transform 
# the addresses from the Madrid City 
# Council to a OSM XML file.
#
# Santiago Crespo 2016
# https://creativecommons.org/publicdomain/zero/1.0/

OUT_FILE="Direcciones de Madrid.osm"
COUNTER=0

echo "# STEP 1/6 Downloading csv and rdf files from datos.madrid.es"
# Download the page with the links
wget -nv "http://datos.madrid.es/portal/site/egob/menuitem.c05c1f754a33a9fbe4b2e4b284f1a5a0/?vgnextoid=b3c41f3cf6a6c410VgnVCM2000000c205a0aRCRD&amp" -O callejero.html
# Download csv "Relación de direcciones vigentes, con coordenadas"
URL_CALLEJERO=`grep "3-callejero" callejero.html | perl -pe 's/>/\n/g'  | grep csv | grep "3-callejero" | awk -F '"' '{print "http://datos.madrid.es/"$6}'`
URL_RDF=`grep rdf callejero.html | grep href | awk -F '"' '{print "http://datos.madrid.es/"$6}'`
## District, suburb and addr information
wget -nv http://datos.madrid.es/egob/catalogo/200078-1-distritos-barrios.csv
wget -nv http://datos.madrid.es/egob/catalogo/200078-4-distritos-barrios.csv
wget -nv "$URL_CALLEJERO"

# Download rdf with the source:date information
wget -nv "$URL_RDF" -O callejero.rdf
FECHA=`grep "dct:modified" callejero.rdf | awk -F '>' '{print $2}' | awk -F 'T' '{print $1}'`

echo "# STEP 2/6 Converting to UTF-8 and modifying some fields"
# Convert to UTF-8, change coordinate fields name (UTM ETRS89 = EPSG:25830)
iconv -f ISO-8859-15 -t UTF-8 "213605-3-callejero oficial madrid.csv" | perl -pe 's/UTMX_ETRS/x/g' | perl -pe 's/UTMY_ETRS/y/g' > callejero-25830.csv
iconv -f ISO-8859-15 -t UTF-8 "200078-1-distritos-barrios.csv" | awk -F ';' '{print $1";"$2";"$4}' | perl -pe 's/  //g' | perl -pe 's/ "/"/g' | tail -n +2 > barrios.csv
iconv -f ISO-8859-15 -t UTF-8 "200078-4-distritos-barrios.csv" | awk -F ';' '{print $2";"$4}' | perl -pe 's/  //g' | perl -pe 's/ "/"/g' | tail -n +2 > distritos.csv

# Filter to get only portal and garage nodes
egrep 'PORTAL|GARAJE' callejero-25830.csv > /tmp/y ; mv /tmp/y callejero-25830.csv

echo "# STEP 3/6 Composing full street name and fixing some capitalization"
while IFS=$';' read -r -a arry
do
  VIA_CLASE="${arry[1]}"
  VIA_PAR="${arry[2]}"
  VIA_NOMBRE_ACENTOS="${arry[4]}"
  VIA_CLASE_MINUSCULAS=${VIA_CLASE,,}
  VIA_NOMBRE_ACENTOS_MINUSCULAS=${VIA_NOMBRE_ACENTOS,,}
  VIA_NOMBRE_ACENTOS_PRIMERA_MAYUSCULA=`echo $VIA_NOMBRE_ACENTOS_MINUSCULAS | sed -e "s/\b\(.\)/\u\1/g"`
  NOMBRE="${VIA_CLASE_MINUSCULAS^} ${VIA_PAR,,} ${VIA_NOMBRE_ACENTOS_PRIMERA_MAYUSCULA^}"
  echo ''${arry[0]}';'$NOMBRE';'${arry[5]}';'${arry[6]}';'${arry[7]}';'${arry[8]}';'${arry[9]}';'${arry[10]}';'${arry[11]}';'${arry[12]}';'${arry[15]}';'${arry[16]}'' >> c
done < callejero-25830.csv

mv c callejero-25830.csv

echo "# STEP 4/6 Reprojecting fom EPSG:25830 to EPSG:4326"
# Prepara la reproyección de EPSG:25830 a EPSG:4326:
  echo '<OGRVRTDataSource>
  <OGRVRTLayer name="callejero-25830">
  <SrcDataSource>callejero-25830.csv</SrcDataSource>
  <GeometryType>wkbPoint</GeometryType>
  <LayerSRS>+init=epsg:25830 +wktext</LayerSRS>             
  <GeometryField encoding="PointFromColumns" x="x" y="y"/>
  <Field name="name" src="Via_clase via_par Via_nombre_acentos" />
  <Field name="COD_VIA" src="COD_VIA" />
  <Field name="CLASE_APP" src="CLASE_APP" />
  <Field name="NUMERO" src="NUMERO" />
  <Field name="CALIFICADOR" src="CALIFICADOR" />
  <Field name="TIPO_NDP" src="TIPO_NDP" />
  <Field name="COD_NDP" src="COD_NDP" />
  <Field name="DISTRITO" src="DISTRITO" />
  <Field name="BARRIO" src="BARRIO" />
  <Field name="COD_POSTAL" src="COD_POSTAL" />
  </OGRVRTLayer>
  </OGRVRTDataSource>' > callejero.vrt

# Reproject to EPSG:4326
ogr2ogr -lco GEOMETRY=AS_XY -overwrite -f CSV -t_srs EPSG:4326 callejero.csv callejero.vrt

# Remove the first line
tail -n +2 callejero.csv > c ; mv c callejero.csv

echo "# STEP 5/6 Creating OSM file"

# HEADERS
echo '<?xml version="1.0" encoding="UTF-8"?>' > "$OUT_FILE"
echo '<osm version="0.6" generator="madridaddr2osm.sh 1.0">' >> "$OUT_FILE"

while IFS=$',' read -r -a arry
do
  let COUNTER=COUNTER-1
# X,Y,name,COD_VIA,CLASE_APP,NUMERO,CALIFICADOR,TIPO_NDP,COD_NDP,DISTRITO,BARRIO,COD_POSTAL
  echo '  <node id="'$COUNTER'" lat="'${arry[1]}'" lon="'${arry[0]}'">' >> "$OUT_FILE"
  echo '    <tag k="addr:street" v="'${arry[2]}'"/>' >> "$OUT_FILE"

# If there a letter in the housenumber
   NUMERO_COMPLETO="${arry[5]}"
   if [ -n "${arry[6]}" ] ; then
     NUMERO_COMPLETO="$NUMERO_COMPLETO-${arry[6]}"
   fi

# N=Número; K=Kilómetro; C=Chabola
   if [ "${arry[4]}" = "C" ] ; then
     echo '    <tag k="addr:housenumber" v="'$NUMERO_COMPLETO' (chabola)"/>' >> "$OUT_FILE"
   elif [ "${arry[4]}" = "K" ] ; then
     echo '    <tag k="addr:housenumber" v="km '$NUMERO_COMPLETO'"/>' >> "$OUT_FILE"
   elif [ "${arry[4]}" = "N" ] ; then
     echo '    <tag k="addr:housenumber" v="'$NUMERO_COMPLETO'"/>' >> "$OUT_FILE"
   else
     echo "ERROR: $NUMERO_COMPLETO ${arry[4]}"
   fi

# TIPO_NDP
   if [ "${arry[7]}" = "PORTAL" ] ; then
     echo '    <tag k="building" v="yes"/>' >> "$OUT_FILE"
     echo '    <tag k="entrance" v="main"/>' >> "$OUT_FILE"
     echo '    <tag k="door" v="yes"/>' >> "$OUT_FILE"
#   elif [ "${arry[7]}" = "FRENTE FACHADA" ] ; then
#     echo '    <tag k="building" v="yes"/>' >> "$OUT_FILE"
   elif [ "${arry[7]}" = "GARAJE" ] ; then
     echo '    <tag k="building" v="garages"/>' >> "$OUT_FILE"
     echo '    <tag k="entrance" v="yes"/>' >> "$OUT_FILE"
     echo '    <tag k="door" v="overhead"/>' >> "$OUT_FILE"
#   elif [ "${arry[7]}" = "JARDIN" ] ; then
#     echo '    <tag k="leisure" v="garden"/>' >> "$OUT_FILE"
#   elif [ "${arry[7]}" = "PARCELA" ] ; then
#     echo '    <tag k="landuse" v="allotments"/>' >> "$OUT_FILE" # I wish they were
   fi

# Districts
  COD_DISTRITO="${arry[9]}"
  DISTRITO=`grep $COD_DISTRITO distritos.csv | awk -F '"' '{print $4}'`
  DISTRITO_MINUSCULAS=${DISTRITO,,}
  DISTRITO_PRIMERA_MAYUSCULA=`echo $DISTRITO_MINUSCULAS | sed -e "s/\b\(.\)/\u\1/g"`
  echo '    <tag k="addr:district" v="'$DISTRITO_PRIMERA_MAYUSCULA'"/>' >> "$OUT_FILE"

# Suburbs
  COD_BARRIO=`printf "%02d\n" "${arry[10]}"`
  BARRIO=`grep '"'$COD_BARRIO'";"'$COD_DISTRITO'"' barrios.csv | awk -F '"' '{print $6}'`
  BARRIO_MINUSCULAS=${BARRIO,,}
  BARRIO_PRIMERA_MAYUSCULA=`echo $BARRIO_MINUSCULAS | sed -e "s/\b\(.\)/\u\1/g"`
  echo '    <tag k="addr:suburb" v="'$BARRIO_PRIMERA_MAYUSCULA'"/>' >> "$OUT_FILE"

  echo '    <tag k="addr:postcode" v="'${arry[11]}'"/>' >> "$OUT_FILE"
  echo '    <tag k="madridcity:street_id" v="'${arry[3]}'"/>' >> "$OUT_FILE"
  echo '    <tag k="madridcity:addr_id" v="'${arry[8]}'"/>' >> "$OUT_FILE"
  echo '    <tag k="source" v="Ayuntamiento de Madrid"/>' >> "$OUT_FILE"
  echo '    <tag k="source:date" v="'$FECHA'"/>' >> "$OUT_FILE"
  echo '  </node>' >> "$OUT_FILE"
done < callejero.csv

echo '</osm>' >> "$OUT_FILE"

echo "# STEP 6/6 Fixing more capitalization errors"
# Arregla preposiciones en mayúscula y números romanos en minúsculas
perl -pe 's/ De / de /g' "$OUT_FILE" | perl -pe 's/ Del / del /g' | perl -pe 's/ La / la /g' | perl -pe 's/ La / la /g' | perl -pe 's/ Las / las /g' | perl -pe 's/ Los / los /g' | perl -pe 's/ Y / y /g' | perl -pe 's/ A / a /g' | perl -pe 's/ En / en /g' | perl -pe 's/ Ii"/ II"/g' | perl -pe 's/ Iii"/ III"/g' | perl -pe 's/ Iv"/ IV"/g' | perl -pe 's/ Vi"/ VI"/g' | perl -pe 's/ Vii"/ VII"/g' | perl -pe 's/ Viii/ VIII/g' | perl -pe 's/ Ix"/ IX"/g' | perl -pe 's/ Xi"/ XI"/g' | perl -pe 's/ Xii"/ XII"/g' | perl -pe 's/ Xiii"/ XIII"/g' | perl -pe 's/ Xxiii"/ XXIII"/g' | perl -pe 's/ Don / don /g' | perl -pe 's/ Doña / doña /g' > o ; mv o "$OUT_FILE" && echo "$OUT_FILE created :)"

#!/bin/bash
FILE="$1"
SRC="$2/$FILE"
DST="$3"

cp $SRC/de.txt "$DST/de-DE/$FILE"
cp $SRC/el.txt "$DST/el/$FILE"
cp $SRC/en.txt "$DST/en-US/$FILE"
cp $SRC/es.txt "$DST/es-MX/$FILE"
cp $SRC/fr.txt "$DST/fr-FR/$FILE"
cp $SRC/it.txt "$DST/it/$FILE"
cp $SRC/nl.txt "$DST/nl-NL/$FILE"
cp $SRC/pl.txt "$DST/pl/$FILE"
cp $SRC/pt.txt "$DST/pt-BR/$FILE"
cp $SRC/ru.txt "$DST/ru/$FILE"
cp $SRC/sv.txt "$DST/sv/$FILE"

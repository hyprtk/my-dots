#!/bin/bash

for f in *.png; do
  magick -verbose "$f" -resize 2560x "$f"
done   
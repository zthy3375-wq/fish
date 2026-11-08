# Third-party notices

- Leaflet 1.9.4: BSD-2-Clause, https://github.com/Leaflet/Leaflet/blob/v1.9.4/LICENSE . Distributed through npm with its license.
- ZXing Android Embedded 4.3.0 and ZXing core 3.5.3: Apache-2.0, https://github.com/journeyapps/zxing-android-embedded and https://github.com/zxing/zxing . Used as Gradle dependencies, not copied source.
- `src/data/campus-geometry.json` and `src/data/campus-places.json`: OpenStreetMap contributor data retrieved 2026-11-08 through Overpass. © OpenStreetMap contributors, available under the Open Database License (ODbL) 1.0: https://www.openstreetmap.org/copyright and https://opendatacommons.org/licenses/odbl/1-0/ . These datasets retain their ODbL licensing independently of the application code's MIT license. The same attribution is displayed on the map. This repository distributes the derived data in machine-readable JSON. Source query: ways with highway/building tags in bbox (36.563,114.485,36.584,114.511), way 226564123, relation 21262225, `out geom`.

Research references and fixed revisions are listed in docs/V083-NATIVE-LIFE.md. No code, images, application assets or tests from the researched campus apps were copied into this implementation.

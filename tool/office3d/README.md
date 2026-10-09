# assets/office3d/three.min.js

A tree-shaken three.js r180 subset (only the classes `entry.js` exports),
bundled as a classic IIFE exposing `window.THREE`, for the Kantor 3D WebView
page `assets/office3d/index.html`.

    npm i three@0.180.0 esbuild
    npx esbuild tool/office3d/entry.js --bundle --minify --format=iife \
      --global-name=THREE --legal-comments=none --outfile=/tmp/t.js
    { echo '/*! three.js r180 subset | MIT License | Copyright 2010-2025 three.js authors | https://threejs.org */'; cat /tmp/t.js; } > assets/office3d/three.min.js

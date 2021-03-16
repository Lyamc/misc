@ECHO OFF
ffmpeg -i "%~1" ^
-map 0:v:0 -map 0:a:0? ^
-map_metadata -1 ^
-af aresample=resampler=soxr -ar 48000 ^
-c:a:0 aac -b:a:0 320k ^
-c:v:0 libx264 -crf 20 -preset slow ^
-movflags +faststart ^
"%~dp0%~n1-reencode.mp4"
sleep 5

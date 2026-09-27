// Heroes of the Four Tiers - standalone launcher.
// Serves the embedded game on 127.0.0.1 and opens it in an app window (Edge/Chrome --app),
// falling back to the default browser. Saves go to a "saves" folder next to the exe.
package main

import (
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"net"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"runtime"
	"sort"
	"strings"
	"sync/atomic"
	"time"
)

//go:embed web
var webFS embed.FS

var lastPing atomic.Int64
var gotPing atomic.Bool
var saveName = regexp.MustCompile(`^[A-Za-z0-9 _\-\.]{1,64}$`)

func saveDir() string {
	exe, err := os.Executable()
	if err == nil {
		d := filepath.Join(filepath.Dir(exe), "saves")
		if os.MkdirAll(d, 0o755) == nil {
			test := filepath.Join(d, ".w")
			if f, err := os.Create(test); err == nil {
				f.Close()
				os.Remove(test)
				return d
			}
		}
	}
	cfg, _ := os.UserConfigDir()
	d := filepath.Join(cfg, "HeroesFourTiers", "saves")
	os.MkdirAll(d, 0o755)
	return d
}

func main() {
	dir := saveDir()
	sub, _ := fs.Sub(webFS, "web")
	mux := http.NewServeMux()
	mux.Handle("/", http.FileServer(http.FS(sub)))
	mux.HandleFunc("/api/ping", func(w http.ResponseWriter, r *http.Request) {
		lastPing.Store(time.Now().Unix())
		gotPing.Store(true)
		w.Write([]byte("ok"))
	})
	mux.HandleFunc("/api/saves", func(w http.ResponseWriter, r *http.Request) {
		type item struct {
			Name string `json:"name"`
			Time int64  `json:"time"`
		}
		out := []item{}
		ents, _ := os.ReadDir(dir)
		for _, e := range ents {
			if strings.HasSuffix(e.Name(), ".json") {
				info, _ := e.Info()
				out = append(out, item{strings.TrimSuffix(e.Name(), ".json"), info.ModTime().Unix()})
			}
		}
		sort.Slice(out, func(i, j int) bool { return out[i].Time > out[j].Time })
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(out)
	})
	mux.HandleFunc("/api/save", func(w http.ResponseWriter, r *http.Request) {
		name := r.URL.Query().Get("name")
		if !saveName.MatchString(name) || strings.Contains(name, "..") {
			http.Error(w, "bad name", 400)
			return
		}
		p := filepath.Join(dir, name+".json")
		switch r.Method {
		case http.MethodGet:
			b, err := os.ReadFile(p)
			if err != nil {
				http.Error(w, "not found", 404)
				return
			}
			w.Header().Set("Content-Type", "application/json")
			w.Write(b)
		case http.MethodPost:
			b, err := io.ReadAll(io.LimitReader(r.Body, 64<<20))
			if err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			if err := os.WriteFile(p, b, 0o644); err != nil {
				http.Error(w, err.Error(), 500)
				return
			}
			w.Write([]byte("ok"))
		case http.MethodDelete:
			os.Remove(p)
			w.Write([]byte("ok"))
		}
	})
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
	url := fmt.Sprintf("http://%s/", ln.Addr().String())
	fmt.Println(url)
	go http.Serve(ln, mux)
	cmd := openWindow(url)
	if cmd != nil {
		// If we own the app window's process, quit when it closes.
		started := time.Now()
		cmd.Wait()
		if time.Since(started) > 8*time.Second {
			os.Exit(0)
		}
		// The browser handed the window to an existing process: fall back to the heartbeat.
	}
	start := time.Now()
	for {
		time.Sleep(5 * time.Second)
		if gotPing.Load() {
			if time.Now().Unix()-lastPing.Load() > 300 {
				os.Exit(0)
			}
		} else if time.Since(start) > 5*time.Minute {
			os.Exit(0)
		}
	}
}

func profileDir() string {
	cfg, err := os.UserCacheDir()
	if err != nil {
		cfg = os.TempDir()
	}
	d := filepath.Join(cfg, "HeroesFourTiers", "browser-profile")
	os.MkdirAll(d, 0o755)
	return d
}

func openWindow(url string) *exec.Cmd {
	args := []string{"--app=" + url, "--user-data-dir=" + profileDir(), "--window-size=1440,900", "--no-first-run", "--no-default-browser-check",
		"--disable-background-timer-throttling", "--autoplay-policy=no-user-gesture-required", "--disable-renderer-backgrounding", "--disable-backgrounding-occluded-windows"}
	var candidates []string
	switch runtime.GOOS {
	case "windows":
		for _, env := range []string{"ProgramFiles(x86)", "ProgramFiles", "LocalAppData"} {
			base := os.Getenv(env)
			if base == "" {
				continue
			}
			candidates = append(candidates,
				filepath.Join(base, "Microsoft", "Edge", "Application", "msedge.exe"),
				filepath.Join(base, "Google", "Chrome", "Application", "chrome.exe"),
				filepath.Join(base, "BraveSoftware", "Brave-Browser", "Application", "brave.exe"))
		}
	case "darwin":
		candidates = []string{"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome", "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge", "/Applications/Chromium.app/Contents/MacOS/Chromium"}
	default:
		for _, n := range []string{"google-chrome", "chromium", "chromium-browser", "microsoft-edge"} {
			if p, err := exec.LookPath(n); err == nil {
				candidates = append(candidates, p)
			}
		}
	}
	for _, c := range candidates {
		if _, err := os.Stat(c); err == nil {
			cmd := exec.Command(c, args...)
			if cmd.Start() == nil {
				return cmd
			}
		}
	}
	// fallback: default browser
	switch runtime.GOOS {
	case "windows":
		exec.Command("rundll32", "url.dll,FileProtocolHandler", url).Start()
	case "darwin":
		exec.Command("open", url).Start()
	default:
		exec.Command("xdg-open", url).Start()
	}
	return nil
}

import tkinter as tk
from tkinter import ttk, messagebox
import subprocess
import threading
import os
import platform
import shutil

PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))


def get_demo_commands():
    system_name = platform.system().lower()

    if system_name == "windows":
        return {
            "name": "Windows",
            "start_script": os.path.join("scripts", "start-demo.ps1"),
            "stop_script": os.path.join("scripts", "stop-demo.ps1"),
            "state_file": os.path.join("scripts", ".demo-state.json"),
            "start_command": [
                "powershell.exe",
                "-ExecutionPolicy",
                "Bypass",
                "-WindowStyle",
                "Hidden",
                "-File",
                os.path.join("scripts", "start-demo.ps1"),
                "-ForceRestart",
            ],
            "stop_command": [
                "powershell.exe",
                "-ExecutionPolicy",
                "Bypass",
                "-WindowStyle",
                "Hidden",
                "-File",
                os.path.join("scripts", "stop-demo.ps1"),
            ],
            "requires": "powershell.exe",
        }

    if system_name == "linux":
        return {
            "name": "Linux",
            "start_script": os.path.join("scripts", "start-demo-linux.sh"),
            "stop_script": os.path.join("scripts", "stop-demo-linux.sh"),
            "state_file": os.path.join("scripts", ".demo-state-linux.json"),
            "start_command": ["bash", os.path.join("scripts", "start-demo-linux.sh"), "--force-restart"],
            "stop_command": ["bash", os.path.join("scripts", "stop-demo-linux.sh")],
            "requires": "bash",
        }

    raise RuntimeError(f"Sistema operativo no soportado para el lanzador: {platform.system()}")


def validate_demo_commands(commands):
    if shutil.which(commands["requires"]) is None:
        raise RuntimeError(f"No se encontro '{commands['requires']}' en PATH.")

    missing_scripts = [
        script
        for script in (commands["start_script"], commands["stop_script"])
        if not os.path.exists(os.path.join(PROJECT_ROOT, script))
    ]
    if missing_scripts:
        scripts_text = ", ".join(missing_scripts)
        raise RuntimeError(
            "Asegurese de ejecutar este script desde la carpeta raiz del proyecto. "
            f"No se encontraron: {scripts_text}"
        )


def run_demo_command(arguments):
    startupinfo = None
    if platform.system().lower() == "windows":
        startupinfo = subprocess.STARTUPINFO()
        startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW

    result = subprocess.run(
        arguments,
        startupinfo=startupinfo,
        check=False,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
        cwd=PROJECT_ROOT,
    )
    if result.returncode != 0:
        output = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
        if not output:
            output = f"El comando termino con codigo {result.returncode}."
        raise RuntimeError(output[-4000:])

class DemoLauncherApp:
    def __init__(self, root, commands):
        self.root = root
        self.commands = commands
        self.root.title("Panel de Control - Demo AppPAE")
        self.root.geometry("460x320")
        self.root.minsize(420, 300)
        self.root.resizable(False, False)
        
        # Estilos
        style = ttk.Style()
        style.configure('TButton', font=('Helvetica', 12), padding=10)
        style.configure('TLabel', font=('Helvetica', 10))
        
        # Layout
        self.main_frame = ttk.Frame(root, padding="20 20 20 20")
        self.main_frame.pack(fill=tk.BOTH, expand=True)
        
        self.title_label = ttk.Label(
            self.main_frame,
            text="Sistema de Logística PAE",
            font=('Helvetica', 16, 'bold'),
        )
        self.title_label.pack(pady=(0, 14))
        
        self.status_var = tk.StringVar(value=f"Estado: Detenido ({commands['name']})")
        self.status_label = ttk.Label(self.main_frame, textvariable=self.status_var, foreground="red")
        self.status_label.pack(pady=(0, 14))
        
        self.start_btn = ttk.Button(self.main_frame, text="▶ Iniciar Demo", command=self.start_demo_thread)
        self.start_btn.pack(fill=tk.X, pady=5)
        
        self.stop_btn = ttk.Button(self.main_frame, text="⏹ Detener Demo", command=self.stop_demo_thread, state=tk.DISABLED)
        self.stop_btn.pack(fill=tk.X, pady=5)
        
        self.process = None
        self.is_starting = False
        self.is_stopping = False
        self.refresh_state()
        self.schedule_state_refresh()

    def is_demo_running(self):
        state_path = os.path.join(PROJECT_ROOT, self.commands["state_file"])
        return os.path.exists(state_path)

    def refresh_state(self):
        if self.is_stopping:
            return
        if self.is_demo_running():
            self.on_started()
        elif not self.is_starting and not self.is_stopping:
            self.on_stopped()

    def schedule_state_refresh(self):
        self.refresh_state()
        self.root.after(2000, self.schedule_state_refresh)

    def start_demo_thread(self):
        self.is_starting = True
        self.start_btn.config(state=tk.DISABLED)
        self.stop_btn.config(state=tk.NORMAL)
        self.status_var.set("Estado: Iniciando servicios... (espere)")
        self.status_label.config(foreground="orange")
        threading.Thread(target=self.run_start_script, daemon=True).start()

    def stop_demo_thread(self):
        self.is_starting = False
        self.is_stopping = True
        self.stop_btn.config(state=tk.DISABLED)
        self.status_var.set("Estado: Deteniendo servicios...")
        self.status_label.config(foreground="orange")
        threading.Thread(target=self.run_stop_script, daemon=True).start()

    def run_start_script(self):
        try:
            run_demo_command(self.commands["start_command"])
            self.root.after(0, self.finish_start)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("Error", f"Fallo al iniciar: {e}"))
            self.root.after(0, self.finish_start)

    def run_stop_script(self):
        try:
            run_demo_command(self.commands["stop_command"])
            self.root.after(0, self.finish_stop)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("Error", f"Fallo al detener: {e}"))
            self.root.after(0, self.finish_stop)

    def finish_start(self):
        self.is_starting = False
        self.refresh_state()

    def finish_stop(self):
        self.is_stopping = False
        self.refresh_state()

    def on_started(self):
        self.status_var.set("Estado: Ejecutando (En vivo)")
        self.status_label.config(foreground="green")
        self.start_btn.config(state=tk.DISABLED)
        self.stop_btn.config(state=tk.NORMAL)

    def on_stopped(self):
        self.status_var.set(f"Estado: Detenido ({self.commands['name']})")
        self.status_label.config(foreground="red")
        self.start_btn.config(state=tk.NORMAL)
        self.stop_btn.config(state=tk.DISABLED)

if __name__ == "__main__":
    os.chdir(PROJECT_ROOT)
    try:
        demo_commands = get_demo_commands()
        validate_demo_commands(demo_commands)
    except Exception as error:
        root = tk.Tk()
        root.withdraw()
        messagebox.showerror("Error", str(error))
        root.destroy()
        raise SystemExit(1) from error

    root = tk.Tk()
    app = DemoLauncherApp(root, demo_commands)
    root.mainloop()

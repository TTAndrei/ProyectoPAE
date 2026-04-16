import tkinter as tk
from tkinter import ttk, messagebox
import subprocess
import threading
import os

class DemoLauncherApp:
    def __init__(self, root):
        self.root = root
        self.root.title("Panel de Control - Demo AppPAE")
        self.root.geometry("400x250")
        self.root.resizable(False, False)
        
        # Estilos
        style = ttk.Style()
        style.configure('TButton', font=('Helvetica', 12), padding=10)
        style.configure('TLabel', font=('Helvetica', 10))
        
        # Layout
        self.main_frame = ttk.Frame(root, padding="20 20 20 20")
        self.main_frame.pack(fill=tk.BOTH, expand=True)
        
        self.title_label = ttk.Label(self.main_frame, text="Sistema de Logística PAE", font=('Helvetica', 16, 'bold'))
        self.title_label.pack(pady=(0, 20))
        
        self.status_var = tk.StringVar(value="Estado: Detenido")
        self.status_label = ttk.Label(self.main_frame, textvariable=self.status_var, foreground="red")
        self.status_label.pack(pady=(0, 20))
        
        self.start_btn = ttk.Button(self.main_frame, text="▶ Iniciar Demo", command=self.start_demo_thread)
        self.start_btn.pack(fill=tk.X, pady=5)
        
        self.stop_btn = ttk.Button(self.main_frame, text="⏹ Detener Demo", command=self.stop_demo_thread, state=tk.DISABLED)
        self.stop_btn.pack(fill=tk.X, pady=5)
        
        self.process = None

    def start_demo_thread(self):
        self.start_btn.config(state=tk.DISABLED)
        self.status_var.set("Estado: Iniciando servicios... (espere)")
        self.status_label.config(foreground="orange")
        threading.Thread(target=self.run_start_script, daemon=True).start()

    def stop_demo_thread(self):
        self.stop_btn.config(state=tk.DISABLED)
        self.status_var.set("Estado: Deteniendo servicios...")
        self.status_label.config(foreground="orange")
        threading.Thread(target=self.run_stop_script, daemon=True).start()

    def run_start_script(self):
        try:
            # Ejecutar script de powershell de inicio sin abrir ventana de consola
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            subprocess.run(
                ["powershell.exe", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "ProyectoPAE/scripts/start-demo.ps1", "-ForceRestart"],
                startupinfo=startupinfo,
                check=True
            )
            self.root.after(0, self.on_started)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("Error", f"Fallo al iniciar: {e}"))
            self.root.after(0, self.on_stopped)

    def run_stop_script(self):
        try:
            startupinfo = subprocess.STARTUPINFO()
            startupinfo.dwFlags |= subprocess.STARTF_USESHOWWINDOW
            subprocess.run(
                ["powershell.exe", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File", "ProyectoPAE/scripts/stop-demo.ps1"],
                startupinfo=startupinfo,
                check=True
            )
            self.root.after(0, self.on_stopped)
        except Exception as e:
            self.root.after(0, lambda: messagebox.showerror("Error", f"Fallo al detener: {e}"))
            self.root.after(0, self.on_started)

    def on_started(self):
        self.status_var.set("Estado: Ejecutando (En vivo)")
        self.status_label.config(foreground="green")
        self.start_btn.config(state=tk.DISABLED)
        self.stop_btn.config(state=tk.NORMAL)

    def on_stopped(self):
        self.status_var.set("Estado: Detenido")
        self.status_label.config(foreground="red")
        self.start_btn.config(state=tk.NORMAL)
        self.stop_btn.config(state=tk.DISABLED)

if __name__ == "__main__":
    if not os.path.exists("ProyectoPAE/scripts/start-demo.ps1"):
        messagebox.showerror("Error", "Asegúrese de ejecutar este script desde la carpeta raíz del proyecto.")
    else:
        root = tk.Tk()
        app = DemoLauncherApp(root)
        root.mainloop()
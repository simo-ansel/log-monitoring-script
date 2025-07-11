
# 📄 Log Monitoring Script

## 🛡️ Log Monitoring Script 

Script Bash per il monitoraggio dei log di sicurezza su sistemi Linux. Il progetto simula attività di **detection** base su un server (Ubuntu), generando un **report dettagliato** delle attività rilevanti e inviandolo via email con backup locale. 

## 📌 Funzionalità  

- Monitoraggio dei **login SSH falliti e riusciti**  
- Rilevamento dell'uso di **comandi sudo** 
- Analisi dei log di **Fail2Ban** e **UFW**  
- Monitoraggio accessi a un file sensibile tramite **auditd**  
- Report automatico formattato e salvato in `~/scheduled_logs/`  
- Invio del report via `mail`  
- Pulizia automatica dei log vecchi oltre 7 giorni

## 🧰 Requisiti  

- Sistema operativo: Linux (testato su Ubuntu) 
- Permessi `sudo`  
- Pacchetti installati: 
	- `auditd`
	- `mailutils` 
	- `rsyslog`, `ufw`, `fail2ban` configurati

Installa i pacchetti richiesti con:

```bash
sudo apt update && sudo apt install auditd mailutils -y 
```
Assicurati che `fail2ban`, `ufw`, `rsyslog`, `auditd` siano attivi:
``` bash
sudo systemctl enable --now auditd fail2ban ufw rsyslog
```

## 🧾 File coinvolti

- Script principale: `monitor-logs.sh`
- Directory dove vengono salvati i report `.log`: `~/scheduled_logs/`
- Contiene login, SSH, sudo: `/var/log/auth.log`
- Attività ban/unban fail2ban: `/var/log/fail2ban.log`
- Connessioni bloccate dal firewall UFW: `/var/log/ufw.log`
- Backup email locale dei report: `/var/mail/<utente>`
- File sensibile monitorato con `auditd`: `~/monitor/secret-script.sh`

## ⚙️ Configurazione iniziale

1.  **Imposta il file da monitorare con auditd**
    
    Lo script monitora letture/scritture su: `~/monitor/secret-script.sh` 
    
    Puoi modificare il valore della variabile `monitor_file` nello script. 

	Il comando usato per la regola è: 
    `sudo auditctl -w /percorso/del/file -p rwxa -k monitor_secret` 
    
2.  **Configura email**
	
	La email di destinazione è impostata nella variabile `email` nello script:
	`email="[REPLACE_WITH_YOUR_EMAIL]"`

	Verifica di aver configurato `mailutils` con `postfix` (locale) o `smtp` (es. per Gmail) se necessario.


## 📧 Configurazione Email (mailutils + postfix con Gmail SMTP)

Lo script utilizza il comando `mail` di `mailutils` per inviare i report di sicurezza via email.  
Per farlo funzionare, puoi configurare **Postfix** come **SMTP relay tramite Gmail**.

### 📦 1. Installa i pacchetti necessari

```bash
sudo apt update
sudo apt install postfix mailutils libsasl2-modules -y 
```

Durante l'installazione di Postfix:

- Scegli **"Internet Site"**
- Imposta `localhost` come **System Mail Name**

---

### 🛠️ 2. Configura Postfix per usare Gmail SMTP

#### 🔐 Crea il file `/etc/postfix/sasl_passwd`:

`[smtp.gmail.com]:587    your_email@gmail.com:your_app_password` 

> ⚠️ _Usa una **App Password** generata da Google, NON la password normale._

#### 🔁 Convertilo in formato hash leggibile da Postfix:

```bash
sudo postmap /etc/postfix/sasl_passwd
sudo chmod 600 /etc/postfix/sasl_passwd /etc/postfix/sasl_passwd.db 
```

#### 📝 Modifica `/etc/postfix/main.cf`

Aggiungi in fondo:
```bash
# === Gmail SMTP Relay ===  
relayhost = [smtp.gmail.com]:587  
smtp_use_tls = yes  
smtp_sasl_auth_enable = yes  
smtp_sasl_password_maps = hash:/etc/postfix/sasl_passwd
smtp_sasl_security_options = noanonymous 
smtp_tls_CAfile = /etc/ssl/certs/ca-certificates.crt 
inet_protocols = ipv4
```
> ⚠️ _Se ci sono righe con le stesse voci, commentale o eliminale._

---

### ▶️ 3. Riavvia e testa Postfix
```bash
sudo systemctl restart postfix
```
Testa l’invio con:
```bash
echo  "Test message" | mail -s "Email di prova" your_email@gmail.com 
```
---

### 🧪 Verifica in caso di problemi

Controlla eventuali errori in:
```bash
sudo tail -n 50 /var/log/mail.log
```
## ▶️ Esecuzione

Esegui manualmente lo script o schedulalo con `cron`:

```bash
chmod +x monitor-logs.sh
./monitor-logs.sh
```

Esempio cronjob giornaliero:

```bash
crontab -e # Aggiungi: 0 7 * * * /percorso/assoluto/monitor-logs.sh
```
----------

## 📤 Esempio di output

### 🔐 Login SSH falliti

```bash
Date                 | IP              | User      
--------------------------------------------------------------
2025-07-09 14:00:17  | 192.168.1.10    | utente1  
```


### ✅ Login SSH riusciti

```
Date                 | IP              | User      
--------------------------------------------------------------
2025-07-10 14:13:52  | 192.168.1.10    | utente1   
```


### 🧯 Comandi sudo

```
User            | Command
--------------------------------------------------------------
utente1         | /usr/bin/rm test.sh
```

### 🧱 Fail2Ban

```
Operation         | IP              | Date                 
--------------------------------------------------------------
Ban               | 192.168.1.2     | 2025-07-08 09:26:38 
Unban             | 192.168.1.2     | 2025-07-08 09:36:38  
```

### 🔥 UFW – Connessioni bloccate

```
Source IP        | Destination IP   | Port     
--------------------------------------------------------------
192.168.1.10     | 192.168.1.5      | 8080    
```

### 📜 Accessi auditd al file segreto

```
Date                | User            | File                                              
--------------------------------------------------------------------------------------
2025-07-11 08:12:38 | utente1         | /home/utente1/monitor/secret-script.sh` 
```

## 📦 Output finale del terminale

```
Report completato!
Output salvato in: /home/utente1/scheduled_logs/monitor logs-2025-07-11_08-21-28.log
Email inviata a: your_email@gmail.com
Backup locale in: /var/mail/utente1
```


;;; erc-services.el --- Identify to NickServ  -*- lexical-binding:t -*-

;; Copyright (C) 2002-2004, 2006-2021 Free Software Foundation, Inc.

;; Maintainer: Amin Bandali <bandali@gnu.org>
;; URL: https://www.emacswiki.org/emacs/ErcNickserv

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; There are two ways to go about identifying yourself automatically to
;; NickServ with this module.  The more secure way is to listen for identify
;; requests from the user NickServ.  Another way is to identify yourself to
;; NickServ directly after a successful connection and every time you change
;; your nickname.  This method is rather insecure, though, because no checks
;; are made to test if NickServ is the real NickServ for a given network or
;; server.

;; As a default, ERC has the data for the official nickname services
;; on the networks Austnet, BrasNET, Dalnet, freenode, GalaxyNet,
;; GRnet, Libera.Chat, and Slashnet.  You can add more by using
;; M-x customize-variable RET erc-nickserv-alist.

;; Usage:
;;
;; Put into your .emacs:
;;
;; (require 'erc-services)
;; (erc-services-mode 1)
;;
;; Add your nickname and NickServ password to `erc-nickserv-passwords'.
;; Using the Libera.Chat network as an example:
;;
;; (setq erc-nickserv-passwords
;;       '((Libera.Chat (("nickname" "password")))))
;;
;; The default automatic identification mode is autodetection of NickServ
;; identify requests.  Set the variable `erc-nickserv-identify-mode' if
;; you'd like to change this behavior.  You can also change the way
;; automatic identification is handled by using:
;;
;; M-x erc-nickserv-identify-mode
;;
;; If you'd rather not identify yourself automatically but would like access
;; to the functions contained in this file, just load this file without
;; enabling `erc-services-mode'.
;;

;;; Code:

(require 'erc)
(require 'erc-networks)
(eval-when-compile (require 'cl-lib))

;; Customization:

(defgroup erc-services nil
  "Configuration for IRC services.

On some networks, there exists a special type of automated irc bot,
called Services.  Those usually allow you to register your nickname,
post/read memos to other registered users who are currently offline,
and do various other things.

This group allows you to set variables to somewhat automate
communication with those Services."
  :group 'erc)

(defcustom erc-nickserv-identify-mode 'both
  "The mode which is used when identifying to Nickserv.

Possible settings are:.

`autodetect'  - Identify when the real Nickserv sends an identify request.
`nick-change' - Identify when you log in or change your nickname.
`both'        - Do the former if the network supports it, otherwise do the
                latter.
nil           - Disables automatic Nickserv identification.

You can also use \\[erc-nickserv-identify-mode] to change modes."
  :type '(choice (const autodetect)
		 (const nick-change)
		 (const both)
		 (const nil))
  :set (lambda (sym val)
	 (set sym val)
	 ;; avoid recursive load at startup
	 (when (featurep 'erc-services)
	   (erc-nickserv-identify-mode val))))

;;;###autoload(autoload 'erc-services-mode "erc-services" nil t)
(define-erc-module services nickserv
  "This mode automates communication with services."
  ((erc-nickserv-identify-mode erc-nickserv-identify-mode))
  ((remove-hook 'erc-server-NOTICE-functions
		#'erc-nickserv-identify-autodetect)
   (remove-hook 'erc-after-connect
		#'erc-nickserv-identify-on-connect)
   (remove-hook 'erc-nick-changed-functions
		#'erc-nickserv-identify-on-nick-change)
   (remove-hook 'erc-server-NOTICE-functions
		#'erc-nickserv-identification-autodetect)))

;;;###autoload
(defun erc-nickserv-identify-mode (mode)
  "Set up hooks according to which MODE the user has chosen."
  (interactive
   (list (intern (completing-read
		  "Choose Nickserv identify mode (RET to disable): "
		  '(("autodetect") ("nick-change") ("both")) nil t))))
  (add-hook 'erc-server-NOTICE-functions
	    #'erc-nickserv-identification-autodetect)
  (unless erc-networks-mode
    ;; Force-enable networks module, because we need it to set
    ;; erc-network for us.
    (erc-networks-enable))
  (cond ((eq mode 'autodetect)
	 (setq erc-nickserv-identify-mode 'autodetect)
	 (add-hook 'erc-server-NOTICE-functions
		   #'erc-nickserv-identify-autodetect)
	 (remove-hook 'erc-nick-changed-functions
		      #'erc-nickserv-identify-on-nick-change)
	 (remove-hook 'erc-after-connect
		      #'erc-nickserv-identify-on-connect))
	((eq mode 'nick-change)
	 (setq erc-nickserv-identify-mode 'nick-change)
	 (add-hook 'erc-after-connect
		   #'erc-nickserv-identify-on-connect)
	 (add-hook 'erc-nick-changed-functions
		   #'erc-nickserv-identify-on-nick-change)
	 (remove-hook 'erc-server-NOTICE-functions
		      #'erc-nickserv-identify-autodetect))
	((eq mode 'both)
	 (setq erc-nickserv-identify-mode 'both)
	 (add-hook 'erc-server-NOTICE-functions
		   #'erc-nickserv-identify-autodetect)
	 (add-hook 'erc-after-connect
		   #'erc-nickserv-identify-on-connect)
	 (add-hook 'erc-nick-changed-functions
		   #'erc-nickserv-identify-on-nick-change))
	(t
	 (setq erc-nickserv-identify-mode nil)
	 (remove-hook 'erc-server-NOTICE-functions
		      #'erc-nickserv-identify-autodetect)
	 (remove-hook 'erc-after-connect
		      #'erc-nickserv-identify-on-connect)
	 (remove-hook 'erc-nick-changed-functions
		      #'erc-nickserv-identify-on-nick-change)
	 (remove-hook 'erc-server-NOTICE-functions
		      #'erc-nickserv-identification-autodetect))))

(defcustom erc-prompt-for-nickserv-password t
  "Ask for the password when identifying to NickServ."
  :type 'boolean)

(defcustom erc-use-auth-source-for-nickserv-password nil
  "Query auth-source for a password when identifiying to NickServ.
Passwords from `erc-nickserv-passwords' take precedence.  See
function `erc-nickserv-get-password'."
  :version "28.1"
  :type 'boolean)

(defcustom erc-nickserv-passwords nil
  "Passwords used when identifying to NickServ automatically.
`erc-prompt-for-nickserv-password' must be nil for these
passwords to be used.

Example of use:
  (setq erc-nickserv-passwords
        \\='((Libera.Chat ((\"nick-one\" . \"password\")
                        (\"nick-two\" . \"password\")))
          (DALnet ((\"nick\" . \"password\")))))"
  :type '(repeat
	  (list :tag "Network"
		(choice :tag "Network name"
			(const Ars)
			(const Austnet)
			(const Azzurra)
			(const BitlBee)
			(const BRASnet)
			(const DALnet)
			(const freenode)
			(const GalaxyNet)
			(const GRnet)
			(const iip)
                        (const Libera.Chat)
			(const OFTC)
			(const QuakeNet)
			(const Rizon)
			(const SlashNET)
			(symbol :tag "Network name"))
		(repeat :tag "Nickname and password"
			(cons :tag "Identity"
			      (string :tag "Nick")
			      (string :tag "Password"
                                      :secret ?*))))))

;; Variables:

(defcustom erc-nickserv-alist
  '((Ars
     nil nil
     "Census"
     "IDENTIFY" nil nil nil)
    (Austnet
     "NickOP!service@austnet.org"
     "/msg\\s-NickOP@austnet.org\\s-identify\\s-<password>"
     "nickop@austnet.org"
     "identify" nil nil nil)
    (Azzurra
     "NickServ!service@azzurra.org"
     "\^B/ns\\s-IDENTIFY\\s-password\^B"
     "NickServ"
     "IDENTIFY" nil nil nil)
    (BitlBee
     nil nil
     "&bitlbee"
     "identify" nil nil nil)
    (BRASnet
     "NickServ!services@brasnet.org"
     "\^B/NickServ\\s-IDENTIFY\\s-\^_senha\^_\^B"
     "NickServ"
     "IDENTIFY" nil "" nil)
    (DALnet
     "NickServ!service@dal.net"
     "/msg\\s-NickServ@services.dal.net\\s-IDENTIFY\\s-<password>"
     "NickServ@services.dal.net"
     "IDENTIFY" nil nil nil)
    (freenode
     "NickServ!NickServ@services."
     ;; freenode also accepts a password at login, see the `erc'
     ;; :password argument.
     "This\\s-nickname\\s-is\\s-registered.\\s-Please\\s-choose"
     "NickServ"
     "IDENTIFY" nil nil
     ;; See also the 901 response code message.
     "You\\s-are\\s-now\\s-identified\\s-for\\s-")
    (GalaxyNet
     "NS!nickserv@galaxynet.org"
     "Please\\s-change\\s-nicks\\s-or\\s-authenticate."
     "NS@services.galaxynet.org"
     "AUTH" t nil nil)
    (GRnet
     "NickServ!service@irc.gr"
     "This\\s-nickname\\s-is\\s-registered\\s-and\\s-protected."
     "NickServ"
     "IDENTIFY" nil nil
     "Password\\s-accepted\\s--\\s-you\\s-are\\s-now\\s-recognized.")
    (iip
     "Trent@anon.iip"
     "type\\s-/squery\\s-Trent\\s-identify\\s-<password>"
     "Trent@anon.iip"
     "IDENTIFY" nil "SQUERY" nil)
    (Libera.Chat
     "NickServ!NickServ@services.libera.chat"
     ;; Libera.Chat also accepts a password at login, see the `erc'
     ;; :password argument.
     "This\\s-nickname\\s-is\\s-registered.\\s-Please\\s-choose"
     "NickServ"
     "IDENTIFY" nil nil
     ;; See also the 901 response code message.
     "You\\s-are\\s-now\\s-identified\\s-for\\s-")
    (OFTC
     "NickServ!services@services.oftc.net"
     ;; OFTC's NickServ doesn't ask you to identify anymore.
     nil
     "NickServ"
     "IDENTIFY" nil nil
     "You\\s-are\\s-successfully\\s-identified\\s-as\\s-\^B")
    (Rizon
     "NickServ!service@rizon.net"
     "This\\s-nickname\\s-is\\s-registered\\s-and\\s-protected."
     "NickServ"
     "IDENTIFY" nil nil
     "Password\\s-accepted\\s--\\s-you\\s-are\\s-now\\s-recognized.")
    (QuakeNet
     nil nil
     "Q@CServe.quakenet.org"
     "auth" t nil nil)
    (SlashNET
     "NickServ!services@services.slashnet.org"
     "/msg\\s-NickServ\\s-IDENTIFY\\s-\^_password"
     "NickServ@services.slashnet.org"
     "IDENTIFY" nil nil nil))
   "Alist of NickServer details, sorted by network.
Every element in the list has the form
  (SYMBOL NICKSERV REGEXP NICK KEYWORD USE-CURRENT ANSWER SUCCESS-REGEXP)

SYMBOL is a network identifier, a symbol, as used in `erc-networks-alist'.
NICKSERV is the description of the nickserv in the form nick!user@host.
REGEXP is a regular expression matching the message from nickserv.
NICK is nickserv's nickname.  Use nick@server where necessary/possible.
KEYWORD is the keyword to use in the reply message to identify yourself.
USE-CURRENT indicates whether the current nickname must be used when
  identifying.
ANSWER is the command to use for the answer.  The default is `privmsg'.
SUCCESS-REGEXP is a regular expression matching the message nickserv
  sends when you've successfully identified.
The last two elements are optional."
   :type '(repeat
	   (list :tag "Nickserv data"
		 (symbol :tag "Network name")
		 (choice (string :tag "Nickserv's nick!user@host")
			 (const :tag "No message sent by Nickserv" nil))
		 (choice (regexp :tag "Identify request sent by Nickserv")
			 (const :tag "No message sent by Nickserv" nil))
		 (string :tag "Identify to")
		 (string :tag "Identify keyword")
		 (boolean :tag "Use current nick in identify message?")
		 (choice :tag "Command to use (optional)"
		  (string :tag "Command")
		  (const :tag "No special command necessary" nil))
		 (choice :tag "Detect Success"
			 (regexp :tag "Pattern to match")
			 (const :tag "Do not try to detect success" nil)))))


(define-inline erc-nickserv-alist-sender (network &optional entry)
  (inline-letevals (network entry)
    (inline-quote (nth 1 (or ,entry (assoc ,network erc-nickserv-alist))))))

(define-inline erc-nickserv-alist-regexp (network &optional entry)
  (inline-letevals (network entry)
    (inline-quote (nth 2 (or ,entry (assoc ,network erc-nickserv-alist))))))

(define-inline erc-nickserv-alist-nickserv (network &optional entry)
  (inline-letevals (network entry)
    (inline-quote (nth 3 (or ,entry (assoc ,network erc-nickserv-alist))))))

(define-inline erc-nickserv-alist-ident-keyword (network &optional entry)
  (inline-letevals (network entry)
    (inline-quote (nth 4 (or ,entry (assoc ,network erc-nickserv-alist))))))

(define-inline erc-nickserv-alist-use-nick-p (network &optional entry)
  (inline-letevals (network entry)
    (inline-quote (nth 5 (or ,entry (assoc ,network erc-nickserv-alist))))))

(define-inline erc-nickserv-alist-ident-command (network &optional entry)
  (inline-letevals (network entry)
    (inline-quote (nth 6 (or ,entry (assoc ,network erc-nickserv-alist))))))

(define-inline erc-nickserv-alist-identified-regexp (network &optional entry)
  (inline-letevals (network entry)
    (inline-quote (nth 7 (or ,entry (assoc ,network erc-nickserv-alist))))))

;; Functions:

(defcustom erc-nickserv-identified-hook nil
  "Run this hook when NickServ acknowledged successful identification.
Hooks are called with arguments (NETWORK NICK)."
  :type 'hook)

(defun erc-nickserv-identification-autodetect (_proc parsed)
  "Check for NickServ's successful identification notice.
Make sure it is the real NickServ for this network and that it has
specifically confirmed a successful identification attempt.
If this is the case, run `erc-nickserv-identified-hook'."
  (let* ((network (erc-network))
	 (sender (erc-nickserv-alist-sender network))
	 (success-regex (erc-nickserv-alist-identified-regexp network))
	 (sspec (erc-response.sender parsed))
	 (nick (car (erc-response.command-args parsed)))
	 (msg (erc-response.contents parsed)))
    ;; continue only if we're sure it's the real nickserv for this network
    ;; and it's told us we've successfully identified
    (when (and sender (equal sspec sender)
	       success-regex
	       (string-match success-regex msg))
      (erc-log "NickServ IDENTIFY success notification detected")
      (run-hook-with-args 'erc-nickserv-identified-hook network nick)
      nil)))

(defun erc-nickserv-identify-autodetect (_proc parsed)
  "Identify to NickServ when an identify request is received.
Make sure it is the real NickServ for this network.
If `erc-prompt-for-nickserv-password' is non-nil, prompt the user for the
password for this nickname, otherwise try to send it automatically."
  (unless (and (null erc-nickserv-passwords)
               (null erc-prompt-for-nickserv-password)
               (null erc-use-auth-source-for-nickserv-password))
    (let* ((network (erc-network))
	   (sender (erc-nickserv-alist-sender network))
	   (identify-regex (erc-nickserv-alist-regexp network))
	   (sspec (erc-response.sender parsed))
	   (nick (car (erc-response.command-args parsed)))
	   (msg (erc-response.contents parsed)))
      ;; continue only if we're sure it's the real nickserv for this network
      ;; and it's asked us to identify
      (when (and sender (equal sspec sender)
		 identify-regex
		 (string-match identify-regex msg))
	(erc-log "NickServ IDENTIFY request detected")
        (erc-nickserv-identify nil nick)
	nil))))

(defun erc-nickserv-identify-on-connect (_server nick)
  "Identify to Nickserv after the connection to the server is established."
  (unless (and (eq erc-nickserv-identify-mode 'both)
               (erc-nickserv-alist-regexp (erc-network)))
    (erc-nickserv-identify nil nick)))

(defun erc-nickserv-identify-on-nick-change (nick _old-nick)
  "Identify to Nickserv whenever your nick changes."
  (unless (and (eq erc-nickserv-identify-mode 'both)
               (erc-nickserv-alist-regexp (erc-network)))
    (erc-nickserv-identify nil nick)))

(defun erc-nickserv-get-password (nick)
  "Return the password for NICK from configured sources.
First, a password for NICK is looked up in
`erc-nickserv-passwords'.  Then, it is looked up in auth-source
if `erc-use-auth-source-for-nickserv-password' is not nil.
Finally, interactively prompt the user, if
`erc-prompt-for-nickserv-password' is true.

As soon as some source returns a password, the sequence of
lookups stops and this function returns it (or returns nil if it
is empty).  Otherwise, no corresponding password was found, and
it returns nil."
  (let (network server port)
    ;; Fill in local vars, switching to the server buffer once only
    (erc-with-server-buffer
     (setq network erc-network
           server erc-session-server
           port erc-session-port))
    (let ((ret
           (or
            (when erc-nickserv-passwords
              (cdr (assoc nick
                          (cl-second (assoc network
                                            erc-nickserv-passwords)))))
            (when erc-use-auth-source-for-nickserv-password
              (let ((secret (cl-first (auth-source-search
                                       :max 1 :require '(:secret)
                                       :host server
                                       ;; Ensure a string for :port
                                       :port (format "%s" port)
                                       :user nick))))
                (when secret
                  (let ((passwd (plist-get secret :secret)))
                    (if (functionp passwd) (funcall passwd) passwd)))))
            (when erc-prompt-for-nickserv-password
              (read-passwd
               (format "NickServ password for %s on %s (RET to cancel): "
                       nick network))))))
      (when (and ret (not (string= ret "")))
        ret))))

(defvar erc-auto-discard-away)

(defun erc-nickserv-send-identify (nick password)
  "Send an \"identify <PASSWORD>\" message to NickServ.
Returns t if the message could be sent, nil otherwise."
  (let* ((erc-auto-discard-away nil)
         (network (erc-network))
         (nickserv-info (assoc network erc-nickserv-alist))
         (nickserv (or (erc-nickserv-alist-nickserv nil nickserv-info)
                       "NickServ"))
         (identify-word (or (erc-nickserv-alist-ident-keyword
                             nil nickserv-info)
                            "IDENTIFY"))
         (nick (if (erc-nickserv-alist-use-nick-p nil nickserv-info)
                   (concat nick " ")
                 ""))
         (msgtype (or (erc-nickserv-alist-ident-command nil nickserv-info)
                      "PRIVMSG")))
    (erc-message msgtype
                 (concat nickserv " " identify-word " " nick password))))

(defun erc-nickserv-call-identify-function (nickname)
  "Call `erc-nickserv-identify' with NICKNAME."
  (declare (obsolete erc-nickserv-identify "28.1"))
  (erc-nickserv-identify nil nickname))

;;;###autoload
(defun erc-nickserv-identify (&optional password nick)
  "Identify to NickServ immediately.
Identification will either use NICK or the current nick if not
provided, and some password obtained through
`erc-nickserv-get-password' (which see).  If no password can be
found, an error is reported trough `erc-error'.

Interactively, the user will be prompted for NICK, an empty
string meaning to default to the current nick.

Returns t if the identify message could be sent, nil otherwise."
  (interactive
   (list
    nil
    (read-from-minibuffer "Nickname: " nil nil nil
                          'erc-nick-history-list (erc-current-nick))))
  (unless (and nick (not (string= nick "")))
    (setq nick (erc-current-nick)))
  (unless password
    (setq password (erc-nickserv-get-password nick)))
  (if password
      (erc-nickserv-send-identify nick password)
    (erc-error "Cannot find a password for nickname %s"
               nick)
    nil))

(provide 'erc-services)


;;; erc-services.el ends here
;;
;; Local Variables:
;; generated-autoload-file: "erc-loaddefs.el"
;; End:
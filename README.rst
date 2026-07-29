=======
haproxy
=======

Install, configure and run ``haproxy``.

.. note::

    See the full `Salt Formulas installation and usage instructions
    <http://docs.saltstack.com/en/latest/topics/development/conventions/formulas.html>`_.

Available states
================

.. contents::
    :local:

Use the supplied haproxy.cfg for a flat file approach,
or the jinja template and the pillar for a salt approach.

``haproxy``
-----------

Install, configure and run ``haproxy`` service.

``haproxy.install``
-------------------

Install ``haproxy`` from packages.

If ``log_file_path`` is set, this state also creates the directory containing it
and manages the rsyslog drop-in named by ``syslog_file_path`` (by default
``/etc/rsyslog.d/49-haproxy.conf``), replacing the copy shipped in the haproxy
package. rsyslog is restarted whenever that file changes or the haproxy package
is installed, since installing the package drops a config into ``/etc/rsyslog.d``
without restarting rsyslog itself (Debian bug #790871).

When ``global:chroot:enable`` is set, HAProxy cannot reach ``/dev/log``, so the
drop-in adds a socket inside the chroot and binds it to its own rsyslog ruleset.
Only messages arriving on that socket are written to the log file. On a systemd
host HAProxy's stderr is captured by journald and forwarded back to rsyslog under
the same program name, so without that separation every health check state change
is written to the log file twice; the drop-in discards the forwarded copy, which
remains available through ``journalctl -u haproxy``.

Without chroot, HAProxy logs to the system ``/dev/log`` and its messages can only
be matched by program name, so that duplication cannot be avoided.

``haproxy.config``
------------------

Currently, only a handful of options can be set using the pillar:

- Global

  + log: a list of log targets, each emitted verbatim after ``log``. Defaults to
    ``['/dev/log local0', '/dev/log local1 notice']``. The level argument is a
    ceiling, so a target with no level receives every message; listing both an
    unfiltered target and a ``notice`` one logs anything at notice or above twice
  + stats: enable stats, curently only via a unix socket which can be set to a path
  + user: sets the user haproxy shall run as
  + group: sets the group haproxy shall run as
  + chroot: allows you to turn on chroot and set a directory
  + daemon: allows you to turn daemon mode on and off

- Default

  + log: set the default log
  + mode: sets the mode (i.e. http)
  + retries: sets the number of retries
  + options: an array of options that is simply looped with no special treatment
  + timeouts: an array of timeouts that is simply looped with no special treatment
  + errorfiles: an array of k:v errorfiles to point to the correct file matching an HTTP error code

- Frontend; Frontend(s) is a list of the frontends you desire to have in your haproxy setup
  Per frontend you can set:

  + name: the name haproxy will use for the frontend
  + bind: the bind string: this allows you to set the IP, Port and other paramters for the bind
  + redirect: add a redirect line, an unparsed string like in the backend
  + reqadd: an array of reqadd statements. Looped over and put in the configuration, no parsing
  + default_backend: sets the default backend
  + acls: a list of acls, not parsed, simply looped and put in to the configuration
  + use_backends: a list of use_backend statements, looped over, not parsed

- Backend; Backend(s) is a list of the backends you desire to have in your haproxy setup, per backend you can set:

  + name: set the backend name, used in the frontend references by haproxy
  + balance: set the balance type, string
  + redirect: if set, can be used to redirect; simply a string, not parsed
  + servers: a list of servers this backend will contact, is looped over; per server you can set:

    + name: name of the server for haproxy
    + host: the host to be contacted
    + port: the port to contact the server on
    + check: set to check to enable checking


``haproxy.service``
-------------------

Make sure ``haproxy`` service is running.


Custom state modules
====================

``ssl_cert``
------------

Provides the ``ssl_cert.deployed`` state (``_states/ssl_cert.py``), used by
``haproxy.install`` to deploy certificate bundles to the HAProxy cert
directory.

Behaves identically to ``file.managed`` except:

- Deployment is skipped (with a success result) if the entity certificate in
  the PEM bundle has expired or cannot be parsed. The file is not created or
  updated in that case, so an HAProxy configuration that references it
  explicitly by path will fail to start — making cert expiry visible via
  ``systemctl is-system-running``.
- ``show_changes`` is always ``False`` regardless of any argument passed, to
  prevent private key material from appearing in Salt output.

Requires pyOpenSSL (bundled with Salt 3006).

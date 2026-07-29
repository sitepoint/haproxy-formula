{%-
  set syslog_file_path = salt['pillar.get'](
    'haproxy:syslog_file_path',
    '/etc/rsyslog.d/49-haproxy.conf'
  )
%}

include:
  - haproxy.config
  - haproxy.service
{% for item in salt['pillar.get']('haproxy:include') %}
  - {{ item }}
{% endfor %}

haproxy.install:
  pkg.installed:
    - name: haproxy
{% if salt['pillar.get']('haproxy:require') %}
    - require:
{% for item in salt['pillar.get']('haproxy:require') %}
      - {{ item }}
{% endfor %}
{% endif %}

# Installing the haproxy package drops a config file into
# /etc/rsyslog.d/ without restarting rsyslog, so it is not picked up
# until something else does. See:
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=790871
#
# The same applies whenever we rewrite that file ourselves. A restart
# rather than a reload is needed, because the chroot socket is an input
# and rsyslog only binds inputs at startup.
{% if salt['pkg.version']('rsyslog') %}
Restart rsyslog on haproxy package install:
  service.running:
    - name: rsyslog
    - watch:
      - pkg: haproxy
      - file: haproxy.config
{% if salt['pillar.get']('haproxy:log_file_path') %}
      - file: Deploy {{ syslog_file_path }}
{% endif %}
{% endif %}

# This is so HAProxy can confirm Squid is operational. The only known
# alternative is running a separate webserver for a single file.
/etc/haproxy/errors/200.http:
  file.managed:
    - contents: |
        HTTP/1.0 200 OK
        Cache-Control: no-cache
        Connection: close
        Content-Type: text/html

        <html><body><h1>200 OK</h1>
        The test page was successful.
        </body></html>
    - require:
      - pkg: haproxy.install
    - require_in:
      - service: haproxy.service

{% if 'log_file_path' in salt['pillar.get']('haproxy') %}
Create the HAProxy logging output directory:
  file.directory:
    - name: {{ salt['pillar.get'](
        'haproxy:log_file_path')[::-1].split('/', 1)[1][::-1]
      }}
    - user: root
    - group: adm
    - mode: '0750'
    - require_in:
      - service: haproxy.service
{% endif %}

# Handle rsyslog configuration.
#
# The packaged file is replaced rather than patched. Patching it meant
# matching whichever of two syntaxes Debian happened to ship, and left
# us unable to change anything but the log path. Managing it outright
# also lets the chroot socket be bound to its own rsyslog ruleset,
# which is what keeps journald's copy of HAProxy's stderr out of the
# log file.
{% if salt['pillar.get']('haproxy:log_file_path') %}
Deploy {{ syslog_file_path }}:
  file.managed:
    - name: {{ syslog_file_path }}
    - source: salt://haproxy/files/rsyslog-haproxy.conf
    - template: jinja
    - user: root
    - group: root
    - mode: '0644'
    - require:
      - pkg: haproxy.install
      - file: Create the HAProxy logging output directory
{% endif %}

# Handle logrotate configuration directives.
{% if salt['pillar.get']('haproxy:logrotate') %}
{%
  set logrotate_config = salt['pillar.get'](
    'haproxy:logrotate_file_path', '/etc/logrotate.d/haproxy'
  )
%}
{% if 'log_file_path' in salt['pillar.get']('haproxy') %}
Update HAProxy log file path in {{ logrotate_config }}:
  file.replace:
    - name: {{ logrotate_config }}
    - pattern: '^(\/[^ ]+)\ +{$'
    - repl:  {{
        salt['pillar.get']('haproxy:log_file_path',
                           '/var/log/haproxy.log')
      }} {
    - backup: False
    - require:
      - pkg: haproxy.install
      - file: Create the HAProxy logging output directory
{% endif %}

# Ideally we would just use the append_if_not_found argument, but the
# last line in the logrotate config file needs to contain "}". We need
# to add a setting entry just prior, if it's not found.
{%
  for setting, value in salt['pillar.get'](
    'haproxy:logrotate:updates'
  ).items()
%}
Add {{ setting }} to {{ logrotate_config }}:
  file.replace:
    - name: {{ logrotate_config }}
    - pattern: '^}$'
    - repl: '    {{ setting }}\n}'
    - flags:
      - MULTILINE
    - backup: False
    - unless: grep -q -E '^\s*{{ setting }}(\s.*|$)' {{ logrotate_config }}
    - require:
      - pkg: haproxy.install

{% if value %}
Update {{ setting }} value in {{ logrotate_config }}:
  file.replace:
    - name: {{ logrotate_config }}
    - pattern: '^(\s*{{ setting }})([^\n]\s*.*)?$'
    - repl: '\1 {{ value }}'
    - flags:
      - MULTILINE
    - backup: False
    - require:
      - pkg: haproxy.install
      - file: Add {{ setting }} to {{ logrotate_config }}
{% else %}
Remove {{ setting }} value in {{ logrotate_config }}:
  file.replace:
    - name: {{ logrotate_config }}
    - pattern: '^(\s*{{ setting }})([^\n]\s*.*)?$'
    - repl: '\1'
    - flags:
      - MULTILINE
    - backup: False
    - require:
      - pkg: haproxy.install
      - file: Add {{ setting }} to {{ logrotate_config }}
{% endif %}
{% endfor %}

{%
  for setting in salt['pillar.get'](
    'haproxy:logrotate:deletes'
  )
%}
Delete {{ setting }} from {{ logrotate_config }}:
  file.replace:
    - name: {{ logrotate_config }}
    - pattern: '^\s*{{ setting }}([^\n]\s*.*)?$\n'
    - repl: ''
    - flags:
      - MULTILINE
    - backup: False
    - require:
      - pkg: haproxy.install
{% endfor %}
{% endif %}


# Handle cert dirs and OCSP stapling.
{%- set python_path = "/opt/saltstack/salt/bin" %}
{%- set update_ocsp_path = "/usr/local/sbin/update_ocsp" %}
{%-
  set current_path = salt['environ.get'](
    "PATH",
    (
        "/usr/local/sbin:/usr/local/bin:"
        "/usr/sbin:/usr/bin:"
        "/sbin:/bin"
    ),
  )
%}

Deploy {{ update_ocsp_path }}:
  file.managed:
    - name: {{ update_ocsp_path }}
    - user: root
    - group: root
    - mode: '0700'
    - source: salt://haproxy/files/update_ocsp
    - requires:
      - pkg: haproxy

{%-
  for dir_name in salt["pillar.get"](
    "haproxy:cert_dirs", ["/etc/haproxy/certs"]
  )
%}
{%- set update_ocsp_cmd = update_ocsp_path ~ " " ~ dir_name %}
{{ dir_name }}:
  file.directory:
    - user: root
    - group: {{ salt['pillar.get']('haproxy:global:group', 'haproxy') }}
    - mode: '0750'
    - require:
      - pkg: haproxy

Run '{{ update_ocsp_cmd }}':
  cmd.wait:
    - name: {{ update_ocsp_cmd }}
    - env:
      - PATH: {{ [python_path, current_path]|join(':') }}
    - require:
      - file: Deploy {{ update_ocsp_path }}

Schedule regular update_ocsp executions via cron for {{ dir_name }}:
  cron.present:
    - name: sh -c 'PATH="{{ python_path }}:${PATH}" {{ update_ocsp_cmd }}'
    - identifier: HAPROXY_OCSP_UPDATE-{{ dir_name }}
    - user: root
    - minute: 0
    - hour: '*/6'
    - require:
      - file: {{ update_ocsp_path }}
{%- endfor %}

{%-
  for hap_cert_dir, hap_cert_names in salt["pillar.get"](
    "haproxy:cert_dirs", {}
  ).items()
%}
{%- for ssl_name, ssl_certs in salt['pillar.get']('ssl', {}).items() %}
{%- if ssl_name in hap_cert_names %}
Deploy {{ hap_cert_dir }}{{ ssl_name }}.pem:
  ssl_cert.deployed:
    - name: {{ hap_cert_dir }}{{ ssl_name }}.pem
    - user: root
    - group: www-data
    - mode: '0640'
    - contents: |-
{%- for cert_type in ("key", "certificate", "intermediate", "ca") %}
{%- if cert_type in ssl_certs %}
        {{ ssl_certs[cert_type].rstrip()|indent(8) }}
{%- endif %}
{%- endfor %}
    - require:
      - file: {{ hap_cert_dir }}
    - watch_in:
      - cmd: Run '{{ update_ocsp_path }} {{ hap_cert_dir }}'
      - service: haproxy.service
{%- endif %}
{%- endfor %}
{%- endfor %}

{%-
  set syslog_file_path = salt['pillar.get'](
    'haproxy:syslog_file_path',
    '/etc/rsyslog.d/49-haproxy.conf'
  )
%}

{% if salt['pillar.get']('haproxy:include') %}
include:
{% for item in salt['pillar.get']('haproxy:include') %}
  - {{ item }}
{% endfor %}
{% endif %}

# If on Ubuntu, add a PPA to use the latest HAProxy releases.
{% if salt['grains.get']('osfullname') == 'Ubuntu' %}
haproxy_ppa_repo:
  pkgrepo.managed:
    - ppa: vbernat/haproxy-1.5
    - require_in:
      - pkg: haproxy.install
    - watch_in:
      - pkg: haproxy.install
{% endif %}

haproxy.install:
  pkg.installed:
    - name: haproxy
{% if salt['pillar.get']('haproxy:require') %}
    - require:
{% for item in salt['pillar.get']('haproxy:require') %}
      - {{ item }}
{% endfor %}
{% endif %}

# See bug report: haproxy install should restart rsyslog
# https://bugs.debian.org/cgi-bin/bugreport.cgi?bug=790871
{% if salt['pkg.version']('rsyslog') %}
Restart rsyslog on haproxy package install:
  service.running:
    - name: rsyslog
    - watch:
      - pkg: haproxy
{% if salt['pillar.get']('haproxy:log_file_path') %}
      - file: Update HAProxy log file path in {{ syslog_file_path }}
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

{% if 'log_file_path' in salt['pillar.get']('haproxy') %}
Create the HAProxy logging output directory:
  file.directory:
    - name: {{ salt['pillar.get'](
        'haproxy:log_file_path')[::-1].split('/', 1)[1][::-1]
      }}
    - user: root
    - group: adm
    - mode: '0750'
{% endif %}

# Handle rsyslog configuration directives.
{% if salt['pillar.get']('haproxy:log_file_path') %}
Update HAProxy log file path in {{ syslog_file_path }}:
  file.replace:
    - name: {{ syslog_file_path }}
    - pattern: ^(if\ \$programname\ startswith\ \'haproxy\'\ then)\ .*$
    - repl:  \1 {{ salt['pillar.get']('haproxy:log_file_path') }}
    - backup: False
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
        salt['pillar.get']('haproxy:log_file_path', '/var/log/haproxy.log')
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

# Handle OCSP stapling.
{% if 'ssl' in salt['pillar.items']() %}
/etc/haproxy/certs:
  file.directory:
    - user: root
    - group: {{ salt['pillar.get']('haproxy:global:group', 'haproxy') }}
    - mode: '0750'
    - require:
      - pkg: haproxy

/usr/local/sbin/update_ocsp:
  file.managed:
    - user: root
    - group: root
    - mode: '0700'
    - source: salt://haproxy/files/update_ocsp
    - requires:
      - pkg: haproxy
  cmd.wait:
    - name: /usr/local/sbin/update_ocsp /etc/haproxy/certs
    - require:
      - file: /usr/local/sbin/update_ocsp

Schedule regular update_ocsp executions via cron:
  cron.present:
    - name: /usr/local/sbin/update_ocsp /etc/haproxy/certs
    - identifier: HAPROXY_OCSP_UPDATE
    - user: root
    - minute: 0
    - hour: '*/6'
    - require:
      - file: /usr/local/sbin/update_ocsp

{% for ssl_cert in salt['pillar.get']('ssl') %}
/etc/haproxy/certs/{{ ssl_cert }}.pem:
  file.managed:
    - user: root
    - group: www-data
    - mode: '0640'
    - contents: |
        {{ salt['pillar.get']('ssl:%s:key' % ssl_cert) | indent(8) }}
        {{ salt['pillar.get']('ssl:%s:certificate' % ssl_cert) | indent(8) }}
        {%- if 'intermediate' in salt['pillar.get']('ssl:%s' % ssl_cert) %}
        {{ salt['pillar.get']('ssl:%s:intermediate' % ssl_cert) | indent(8) }}
        {% endif %}
        {%- if 'ca' in salt['pillar.get']('ssl:%s' % ssl_cert) %}
        {{ salt['pillar.get']('ssl:%s:ca' % ssl_cert) | indent(8) }}
        {% endif %}
    - require:
      - file: /etc/haproxy/certs
    - watch_in:
      - cmd: /usr/local/sbin/update_ocsp
{% endfor %}
{% endif %}

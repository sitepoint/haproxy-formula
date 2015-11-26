haproxy.service:
{% if salt['pillar.get']('haproxy:enable', True) %}
  service.running:
    - name: haproxy
    - enable: True
    - reload: True
    - require:
      - pkg: haproxy
        file: haproxy.service
{% if 'ssl' in salt['pillar.items']() %}
{% for ssl_cert in salt['pillar.get']('ssl') %}
      - file: /etc/haproxy/certs/{{ ssl_cert }}.pem
{% endfor %}
{% endif %}
    - watch:
      - file: haproxy.config
{% if 'ssl' in salt['pillar.items']() %}
{% for ssl_cert in salt['pillar.get']('ssl') %}
      - file: /etc/haproxy/certs/{{ ssl_cert }}.pem
{% endfor %}
{% endif %}
{% else %}
  service.dead:
    - name: haproxy
    - enable: False
{% endif %}
  file.replace:
    - name: /etc/default/haproxy
{% if salt['pillar.get']('haproxy:enabled', True) %}
    - pattern: ENABLED=0$
    - repl: ENABLED=1
{% else %}
    - pattern: ENABLED=1$
    - repl: ENABLED=0
{% endif %}
    - show_changes: True

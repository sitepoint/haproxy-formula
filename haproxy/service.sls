include:
  - haproxy.install
  - haproxy.config

haproxy.service:
{% if salt['pillar.get']('haproxy:enable', True) %}
  service.running:
    - name: haproxy
    - enable: True
    - reload: True
    - require:
      - pkg: haproxy
    - watch:
      - file: haproxy.config
{%- if salt['pillar.get']('haproxy:dhparam') %}
      - file: haproxy.dhparam
{%- endif %}
{%- for path in salt["pillar.get"]("haproxy:map_files", []) %}
      - file: HAProxy map file {{ path }}
{%- endfor %}
{% else %}
  service.dead:
    - name: haproxy
    - enable: False
{% endif %}

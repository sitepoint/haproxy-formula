{%- if salt['pillar.get']('haproxy:dhparam') %}
haproxy.dhparam:
  file.managed:
    - name: {{ salt['pillar.get']('haproxy:dhparam_file_path', '/etc/haproxy/dhparam') }}
    - contents_pillar: 'haproxy:dhparam'
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: haproxy.install
{%- endif %}

haproxy.config:
  file.managed:
    - name: {{ salt['pillar.get']('haproxy:config_file_path', '/etc/haproxy/haproxy.cfg') }}
    - source: salt://haproxy/templates/haproxy.jinja
    - template: jinja
    - user: root
    - group: root
    - mode: 644
    - require:
      - pkg: haproxy.install
{%- if salt['pillar.get']('haproxy:dhparam') %}
      - file: {{ salt['pillar.get']('haproxy:dhparam_file_path', '/etc/haproxy/dhparam') }}
{%- endif %}

include:
  - haproxy.install

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
    - require_in:
      - file: haproxy.config
{%- endif %}

{%- for path, mappings in salt["pillar.get"]("haproxy:map_files", {}).items() %}
HAProxy map file {{ path }}:
  file.managed:
    - name: {{ path }}
    - contents: |-
{%- for key, value in mappings.items() %}
        {{ key }}  {{ value }}
{%- endfor %}
    - makedirs: True
    - user: root
    - group: root
    - mode: 644
    - dir_mode: '0755'
    - require:
      - pkg: haproxy.install
    - require_in:
      - file: haproxy.config
{%- endfor %}

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

# Because on Ubuntu we don't have a current HAProxy in the usual repo, we add a PPA
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

{#
 # This is so HAProxy can confirm Squid is operational. The only known
 # alternative is running a separate webserver for a single file.
 #}
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

{% if 'ssl' in salt['pillar.items']() %}
/etc/haproxy/certs:
  file.directory:
    - user: root
    - group: {{ salt['pillar.get']('haproxy:global:group', 'haproxy') }}
    - mode: '0750'
    - require:
      - pkg: haproxy

{% for ssl_cert in salt['pillar.get']('ssl') %}
/etc/haproxy/certs/{{ ssl_cert }}.pem:
  file.managed:
    - user: root
    - group: www-data
    - mode: '0640'
    - contents: |
        {{ salt['pillar.get']('ssl:%s:key' % ssl_cert) | indent(8) }}
        {{ salt['pillar.get']('ssl:%s:certificate' % ssl_cert) | indent(8) }}
        {%- if 'ca' in salt['pillar.get']('ssl:%s' % ssl_cert) %}
        {{ salt['pillar.get']('ssl:%s:ca' % ssl_cert) | indent(8) }}
        {% endif %}
    - require:
      - file: /etc/haproxy/certs
{% endfor %}
{% endif %}

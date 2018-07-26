# haproxy
#
# Meta-state to fully setup haproxy on debian. (or any other distro that has haproxy in their repo)

include:
{% if salt['pillar.get']('haproxy:include') %}
{% for item in salt['pillar.get']('haproxy:include') %}
  - {{ item }}
{% endfor %}
{% endif %}
  - haproxy.install
  - haproxy.service
  - haproxy.config

# We need something more in an sls file than a single include
# statement to avoid Salt issue #48277.
# https://github.com/saltstack/salt/issues/48277
# The fix is expected to arrive in 2017.7.8 or 2018.8.3, after which
# point this hack can disappear.
Work-around for Salt issue 48277:
  test.succeed_without_changes

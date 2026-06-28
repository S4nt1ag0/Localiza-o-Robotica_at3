#!/usr/bin/env python3
import math
import sys
import time

import rosgraph
import rospy
import tf
from rosgraph_msgs.msg import Clock
from nav_msgs.msg import Odometry
from sensor_msgs.msg import LaserScan


EXPECTED_TYPES = {
    "/front/scan": "sensor_msgs/LaserScan",
    "/odometry/filtered": "nav_msgs/Odometry",
    "/gazebo_ground_truth/odom": "nav_msgs/Odometry",
    "/tf": "tf2_msgs/TFMessage",
    "/tf_static": "tf2_msgs/TFMessage",
    "/clock": "rosgraph_msgs/Clock",
    "/cmd_vel": "geometry_msgs/Twist",
}
COMPATIBLE_TYPES = {
    "/tf": {"tf/tfMessage", "tf2_msgs/TFMessage"},
}


def fail(message):
    rospy.logerr(message)
    return False


def main():
    rospy.init_node("check_mapping_topics", anonymous=True)
    ok = True
    published = dict(rospy.get_published_topics(namespace="/"))

    for topic, expected_type in EXPECTED_TYPES.items():
        actual_type = published.get(topic)
        accepted_types = COMPATIBLE_TYPES.get(topic, {expected_type})
        if actual_type not in accepted_types:
            ok = fail("%s: esperado %s, encontrado %s" % (topic, expected_type, actual_type)) and ok
        else:
            rospy.loginfo("OK %-30s %s", topic, actual_type)

    for topic, msg_type in (
        ("/clock", Clock),
        ("/odometry/filtered", Odometry),
        ("/gazebo_ground_truth/odom", Odometry),
    ):
        try:
            rospy.wait_for_message(topic, msg_type, timeout=5.0)
        except rospy.ROSException:
            ok = fail("%s nao publicou dentro de 5 s" % topic) and ok

    scans = []
    deadline = time.monotonic() + 6.0
    while len(scans) < 8 and time.monotonic() < deadline and not rospy.is_shutdown():
        try:
            scans.append(rospy.wait_for_message("/front/scan", LaserScan, timeout=1.0))
        except rospy.ROSException:
            pass

    if len(scans) < 3:
        ok = fail("/front/scan nao forneceu amostras suficientes") and ok
    else:
        last_scan = scans[-1]
        finite_ranges = sum(1 for value in last_scan.ranges if math.isfinite(value))
        stamps = [message.header.stamp.to_sec() for message in scans]
        duration = stamps[-1] - stamps[0]
        frequency = (len(stamps) - 1) / duration if duration > 0 else 0.0
        if last_scan.header.frame_id.lstrip("/") != "front_laser":
            ok = fail("frame do laser inesperado: %s" % last_scan.header.frame_id) and ok
        if not last_scan.ranges or finite_ranges == 0:
            ok = fail("LaserScan vazio ou sem nenhuma distancia finita") and ok
        if frequency < 5.0:
            ok = fail("frequencia do laser baixa: %.2f Hz (minimo 5 Hz)" % frequency) and ok
        if abs((rospy.Time.now() - last_scan.header.stamp).to_sec()) > 1.0:
            ok = fail("timestamp do laser difere do relogio ROS em mais de 1 s") and ok
        rospy.loginfo("Laser: %.2f Hz, %d/%d medidas finitas", frequency, finite_ranges, len(last_scan.ranges))

    listener = tf.TransformListener()
    for parent, child in (("odom", "base_link"), ("base_link", "front_laser")):
        try:
            listener.waitForTransform(parent, child, rospy.Time(0), rospy.Duration(8.0))
            listener.lookupTransform(parent, child, rospy.Time(0))
            rospy.loginfo("OK transformacao %s -> %s", parent, child)
        except (tf.Exception, tf.LookupException, tf.ConnectivityException, tf.ExtrapolationException) as error:
            ok = fail("TF %s -> %s indisponivel: %s" % (parent, child, error)) and ok

    try:
        master = rosgraph.Master(rospy.get_name())
        publishers, _, _ = master.getSystemState()
        nodes = {node for _, topic_nodes in publishers for node in topic_nodes}
        forbidden = sorted(node for node in nodes if "gmapping" in node or "hector_mapping" in node or node == "/amcl")
        if forbidden:
            ok = fail("SLAM/localizacao online detectado; encerre antes de gravar: %s" % ", ".join(forbidden)) and ok
    except rosgraph.MasterException as error:
        ok = fail("nao foi possivel consultar o ROS master: %s" % error) and ok

    if ok:
        rospy.loginfo("Ambiente pronto para gravacao.")
        return 0
    rospy.logerr("Ambiente NAO esta pronto. Corrija os itens acima antes de gravar.")
    return 1


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
import argparse
import bisect
import csv
import math
import os
import sys

import rosbag


def yaw_from_quaternion(q):
    siny = 2.0 * (q.w * q.z + q.x * q.y)
    cosy = 1.0 - 2.0 * (q.y * q.y + q.z * q.z)
    return math.atan2(siny, cosy)


def wrap_angle(angle):
    return math.atan2(math.sin(angle), math.cos(angle))


def message_time(message, bag_time):
    stamp = getattr(getattr(message, "header", None), "stamp", None)
    if stamp is not None and stamp.to_sec() > 0.0:
        return stamp.to_sec()
    return bag_time.to_sec()


def percentile(values, percent):
    ordered = sorted(values)
    if not ordered:
        return float("nan")
    position = (len(ordered) - 1) * percent / 100.0
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    fraction = position - lower
    return ordered[lower] * (1.0 - fraction) + ordered[upper] * fraction


def mean(values):
    return sum(values) / len(values) if values else float("nan")


def standard_deviation(values):
    if not values:
        return float("nan")
    average = mean(values)
    return math.sqrt(sum((value - average) ** 2 for value in values) / len(values))


def read_bag(path):
    estimates = []
    ground_truth = []
    with rosbag.Bag(path, "r") as bag:
        for topic, message, bag_time in bag.read_messages(
                topics=["/amcl_pose", "/gazebo_ground_truth/odom"]):
            stamp = message_time(message, bag_time)
            pose = message.pose.pose
            sample = {
                "time": stamp,
                "frame": message.header.frame_id.lstrip("/"),
                "x": pose.position.x,
                "y": pose.position.y,
                "yaw": yaw_from_quaternion(pose.orientation),
            }
            if topic == "/amcl_pose":
                covariance = message.pose.covariance
                sample["covariance_xy"] = covariance[0] + covariance[7]
                sample["covariance_yaw"] = covariance[35]
                estimates.append(sample)
            else:
                ground_truth.append(sample)
    if not estimates:
        raise RuntimeError("bag sem mensagens em /amcl_pose")
    if not ground_truth:
        raise RuntimeError("bag sem mensagens em /gazebo_ground_truth/odom")
    estimates.sort(key=lambda item: item["time"])
    ground_truth.sort(key=lambda item: item["time"])
    return estimates, ground_truth


def nearest_ground_truth(ground_truth, times, stamp, max_pair_dt):
    index = bisect.bisect_left(times, stamp)
    candidates = []
    if index < len(ground_truth):
        candidates.append(ground_truth[index])
    if index > 0:
        candidates.append(ground_truth[index - 1])
    if not candidates:
        return None
    nearest = min(candidates, key=lambda item: abs(item["time"] - stamp))
    if abs(nearest["time"] - stamp) > max_pair_dt:
        return None
    return nearest


def align_ground_truth(sample, reference_gt, reference_estimate):
    delta_x = sample["x"] - reference_gt["x"]
    delta_y = sample["y"] - reference_gt["y"]
    rotation = wrap_angle(reference_estimate["yaw"] - reference_gt["yaw"])
    cosine = math.cos(rotation)
    sine = math.sin(rotation)
    return {
        "x": reference_estimate["x"] + cosine * delta_x - sine * delta_y,
        "y": reference_estimate["y"] + sine * delta_x + cosine * delta_y,
        "yaw": wrap_angle(sample["yaw"] + rotation),
    }


def analyze(path, method, max_pair_dt):
    estimates, ground_truth = read_bag(path)
    gt_times = [sample["time"] for sample in ground_truth]
    first_gt = nearest_ground_truth(ground_truth, gt_times, estimates[0]["time"], max_pair_dt)
    if first_gt is None:
        raise RuntimeError("nao foi possivel sincronizar a primeira pose com o ground truth")

    same_frame = bool(estimates[0]["frame"] and estimates[0]["frame"] == first_gt["frame"])
    alignment = "direct_same_frame" if same_frame else "initial_se2"
    rows = []
    for estimate in estimates:
        gt = nearest_ground_truth(ground_truth, gt_times, estimate["time"], max_pair_dt)
        if gt is None:
            continue
        aligned_gt = gt if same_frame else align_ground_truth(gt, first_gt, estimates[0])
        dx = estimate["x"] - aligned_gt["x"]
        dy = estimate["y"] - aligned_gt["y"]
        position_error = math.hypot(dx, dy)
        yaw_error = wrap_angle(estimate["yaw"] - aligned_gt["yaw"])
        rows.append({
            "time": estimate["time"],
            "estimate_x": estimate["x"],
            "estimate_y": estimate["y"],
            "estimate_yaw": estimate["yaw"],
            "gt_x": aligned_gt["x"],
            "gt_y": aligned_gt["y"],
            "gt_yaw": aligned_gt["yaw"],
            "position_error": position_error,
            "yaw_error": yaw_error,
            "abs_yaw_error": abs(yaw_error),
            "pair_dt": abs(estimate["time"] - gt["time"]),
            "covariance_xy": estimate["covariance_xy"],
            "covariance_yaw": estimate["covariance_yaw"],
        })
    if not rows:
        raise RuntimeError("nenhum par AMCL/ground truth dentro da tolerancia temporal")

    position_errors = [row["position_error"] for row in rows]
    yaw_errors = [row["yaw_error"] for row in rows]
    absolute_yaw_errors = [abs(value) for value in yaw_errors]
    update_gaps = [rows[index]["time"] - rows[index - 1]["time"] for index in range(1, len(rows))]
    error_changes = [abs(position_errors[index] - position_errors[index - 1])
                     for index in range(1, len(position_errors))]
    duration = rows[-1]["time"] - rows[0]["time"]

    summary = {
        "method": method,
        "bag": os.path.abspath(path),
        "alignment": alignment,
        "samples": len(rows),
        "duration_s": duration,
        "mean_position_error_m": mean(position_errors),
        "rmse_position_m": math.sqrt(mean([value * value for value in position_errors])),
        "final_position_error_m": position_errors[-1],
        "std_position_error_m": standard_deviation(position_errors),
        "p95_position_error_m": percentile(position_errors, 95.0),
        "max_position_error_m": max(position_errors),
        "mean_abs_error_change_m": mean(error_changes),
        "mean_abs_yaw_error_rad": mean(absolute_yaw_errors),
        "rmse_yaw_rad": math.sqrt(mean([value * value for value in yaw_errors])),
        "final_abs_yaw_error_rad": absolute_yaw_errors[-1],
        "std_abs_yaw_error_rad": standard_deviation(absolute_yaw_errors),
        "p95_abs_yaw_error_rad": percentile(absolute_yaw_errors, 95.0),
        "mean_amcl_covariance_xy": mean([row["covariance_xy"] for row in rows]),
        "mean_amcl_covariance_yaw": mean([row["covariance_yaw"] for row in rows]),
        "mean_update_rate_hz": ((len(rows) - 1) / duration if duration > 0.0 else float("nan")),
        "max_update_gap_s": max(update_gaps) if update_gaps else 0.0,
        "max_pair_dt_s": max(row["pair_dt"] for row in rows),
    }
    return rows, summary


def write_metrics_csv(path, rows):
    fields = [
        "time_s", "elapsed_s", "estimate_x_m", "estimate_y_m", "estimate_yaw_rad",
        "gt_x_m", "gt_y_m", "gt_yaw_rad", "position_error_m", "yaw_error_rad",
        "abs_yaw_error_rad", "pair_dt_s", "amcl_covariance_xy", "amcl_covariance_yaw",
    ]
    start = rows[0]["time"]
    with open(path, "w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()
        for row in rows:
            writer.writerow({
                "time_s": "%.9f" % row["time"],
                "elapsed_s": "%.9f" % (row["time"] - start),
                "estimate_x_m": "%.9f" % row["estimate_x"],
                "estimate_y_m": "%.9f" % row["estimate_y"],
                "estimate_yaw_rad": "%.9f" % row["estimate_yaw"],
                "gt_x_m": "%.9f" % row["gt_x"],
                "gt_y_m": "%.9f" % row["gt_y"],
                "gt_yaw_rad": "%.9f" % row["gt_yaw"],
                "position_error_m": "%.9f" % row["position_error"],
                "yaw_error_rad": "%.9f" % row["yaw_error"],
                "abs_yaw_error_rad": "%.9f" % row["abs_yaw_error"],
                "pair_dt_s": "%.9f" % row["pair_dt"],
                "amcl_covariance_xy": "%.9f" % row["covariance_xy"],
                "amcl_covariance_yaw": "%.9f" % row["covariance_yaw"],
            })


def write_summary(path, summary):
    with open(path, "w") as output:
        for key, value in summary.items():
            if isinstance(value, float):
                output.write("%s: %.9f\n" % (key, value))
            else:
                output.write("%s: %s\n" % (key, value))


def write_comparison_csv(path, summaries):
    fields = list(summaries[0].keys())
    with open(path, "w", newline="") as output:
        writer = csv.DictWriter(output, fieldnames=fields)
        writer.writeheader()
        writer.writerows(summaries)


def write_report(path, summaries):
    columns = [
        ("Método", "method"),
        ("Erro médio (m)", "mean_position_error_m"),
        ("RMSE posição (m)", "rmse_position_m"),
        ("Erro final (m)", "final_position_error_m"),
        ("RMSE yaw (rad)", "rmse_yaw_rad"),
        ("Desvio erro pos. (m)", "std_position_error_m"),
        ("P95 erro pos. (m)", "p95_position_error_m"),
    ]
    with open(path, "w") as output:
        output.write("# Comparação AMCL: Hector SLAM vs GMapping\n\n")
        output.write("| " + " | ".join(label for label, _ in columns) + " |\n")
        output.write("| " + " | ".join(["---"] + ["---:"] * (len(columns) - 1)) + " |\n")
        for summary in summaries:
            values = []
            for _, key in columns:
                value = summary[key]
                values.append(("%.6f" % value) if isinstance(value, float) else str(value))
            output.write("| " + " | ".join(values) + " |\n")
        output.write("\nA estabilidade é representada principalmente pelo desvio padrão, P95 e máximo "
                     "do erro, pela variação média entre atualizações e pelo maior intervalo sem atualização.\n")


def write_plots(output_dir, results):
    try:
        import matplotlib
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
    except ImportError as error:
        raise RuntimeError("matplotlib ausente: %s" % error)

    fig, axis = plt.subplots(figsize=(9, 5))
    for method, rows in results.items():
        start = rows[0]["time"]
        axis.plot([row["time"] - start for row in rows],
                  [row["position_error"] for row in rows], label=method)
    axis.set(title="Erro de posição do AMCL", xlabel="Tempo [s]", ylabel="Erro [m]")
    axis.grid(True, alpha=0.3)
    axis.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(output_dir, "comparison_position_error.png"), dpi=150)
    plt.close(fig)

    fig, axis = plt.subplots(figsize=(9, 5))
    for method, rows in results.items():
        start = rows[0]["time"]
        axis.plot([row["time"] - start for row in rows],
                  [row["yaw_error"] for row in rows], label=method)
    axis.set(title="Erro de orientação do AMCL", xlabel="Tempo [s]", ylabel="Erro de yaw [rad]")
    axis.grid(True, alpha=0.3)
    axis.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(output_dir, "comparison_yaw_error.png"), dpi=150)
    plt.close(fig)

    fig, axis = plt.subplots(figsize=(7, 7))
    first_rows = next(iter(results.values()))
    axis.plot([row["gt_x"] for row in first_rows], [row["gt_y"] for row in first_rows],
              color="black", linewidth=2.0, label="ground truth")
    for method, rows in results.items():
        axis.plot([row["estimate_x"] for row in rows], [row["estimate_y"] for row in rows], label=method)
    axis.set(title="Trajetórias estimadas vs ground truth", xlabel="x [m]", ylabel="y [m]")
    axis.axis("equal")
    axis.grid(True, alpha=0.3)
    axis.legend()
    fig.tight_layout()
    fig.savefig(os.path.join(output_dir, "comparison_trajectories.png"), dpi=150)
    plt.close(fig)


def main():
    package_dir = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description="Compara AMCL com ground truth diretamente nas bags.")
    parser.add_argument("--hector-bag", default=os.path.join(package_dir, "results/localization/amcl_hector.bag"))
    parser.add_argument("--gmapping-bag", default=os.path.join(package_dir, "results/localization/amcl_gmapping.bag"))
    parser.add_argument("--output-dir", default=os.path.join(package_dir, "results/metrics"))
    parser.add_argument("--max-pair-dt", type=float, default=0.1,
                        help="Tolerancia maxima para sincronizar AMCL e ground truth [s].")
    args = parser.parse_args()

    if args.max_pair_dt <= 0.0:
        parser.error("--max-pair-dt deve ser positivo")
    os.makedirs(args.output_dir, exist_ok=True)

    bags = {"hector": args.hector_bag, "gmapping": args.gmapping_bag}
    results = {}
    summaries = []
    try:
        for method, path in bags.items():
            if not os.path.isfile(path):
                raise RuntimeError("bag nao encontrada: %s" % path)
            rows, summary = analyze(path, method, args.max_pair_dt)
            results[method] = rows
            summaries.append(summary)
            write_metrics_csv(os.path.join(args.output_dir, "amcl_%s_metrics.csv" % method), rows)
            write_summary(os.path.join(args.output_dir, "amcl_%s_summary.txt" % method), summary)
        write_comparison_csv(os.path.join(args.output_dir, "comparison_summary.csv"), summaries)
        write_report(os.path.join(args.output_dir, "comparison_report.md"), summaries)
        write_plots(args.output_dir, results)
    except (IOError, OSError, RuntimeError, rosbag.bag.ROSBagException) as error:
        print("ERRO: %s" % error, file=sys.stderr)
        return 1

    print("Comparacao concluida: %s" % os.path.abspath(args.output_dir))
    for summary in summaries:
        print("  %s: erro medio=%.4f m, RMSE=%.4f m, erro final=%.4f m, RMSE yaw=%.4f rad" % (
            summary["method"], summary["mean_position_error_m"], summary["rmse_position_m"],
            summary["final_position_error_m"], summary["rmse_yaw_rad"]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
